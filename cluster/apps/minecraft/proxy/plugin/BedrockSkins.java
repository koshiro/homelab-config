package cl.danielriquelme.homelab;

import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.velocitypowered.api.event.Continuation;
import com.velocitypowered.api.event.Subscribe;
import com.velocitypowered.api.event.player.GameProfileRequestEvent;
import com.velocitypowered.api.proxy.Player;
import com.velocitypowered.api.proxy.ProxyServer;
import com.velocitypowered.api.util.GameProfile;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.lang.reflect.Method;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.time.Duration;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.TimeUnit;
import javax.imageio.ImageIO;
import org.slf4j.Logger;

/**
 * Skin actual de Bedrock para los jugadores Java.
 *
 * Geyser/Floodgate suben la skin de Bedrock a la API global de GeyserMC, que la convierte con
 * MineSkin; desde 2026-09 esa subida falla (GeyserMC/Geyser#6699) y Floodgate aplica la última
 * skin que la API tenga guardada para el XUID, aunque sea vieja. Aquí se toma la skin que la
 * tablet envía en cada conexión (datos de cliente de Geyser), se firma con nuestra cuenta de
 * MineSkin y se pone en el perfil antes de entrar al servidor (después de Floodgate, que usa
 * PostOrder.EARLY). Si cambia la skin en Bedrock, basta con reconectarse.
 *
 * Alias Java (variable JAVA_ALIASES): un jugador Java con ese nombre entra con la identidad de un
 * jugador Bedrock (mismo UUID de Floodgate y mismo nombre), así comparte inventarios, posición y
 * whitelist. Formato: "nombreJava=nombreBedrock@uuid" separados por espacios o comas. Recibe la
 * última skin que ese jugador trajo de Bedrock, guardada en BEDROCK_SKIN_STATE (volumen persistente).
 * Sin online-mode cualquiera puede usar ese nombre en Java: igual que con el resto de la whitelist.
 *
 * Geyser y SkinsRestorer se usan por reflexión (son plugins del proxy, sin dependencia de compilación).
 */
public class BedrockSkins {
    private static final String MINESKIN_URL = "https://api.mineskin.org/v2/generate";
    private static final String USER_AGENT = "homelab-bedrock-skins/1.0";
    /** Tiempo máximo que se retiene el login esperando a MineSkin; si tarda más se aplica en vivo. */
    private static final long LOGIN_WAIT_SECONDS = 8;

    private final ProxyServer proxy;
    private final Logger logger;
    private final Path debugDir;
    private final String apiKey;
    private final HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build();
    /** sha256 del PNG → textura firmada (MineSkin también deduplica, esto solo evita la llamada). */
    private final Map<String, CompletableFuture<GameProfile.Property>> textures = new ConcurrentHashMap<>();
    /** nombre Java (minúsculas) → identidad Bedrock que asume. */
    private final Map<String, GameProfile> aliases = new ConcurrentHashMap<>();
    /** UUID Bedrock → última skin firmada (para dársela también a su alias Java). */
    private final Map<UUID, GameProfile.Property> lastTexture = new ConcurrentHashMap<>();
    /** Archivo JSON con lastTexture (sobrevive a los reinicios del proxy); null = solo memoria. */
    private final Path stateFile;

    public BedrockSkins(ProxyServer proxy, Logger logger, Path dataDir) {
        this.proxy = proxy;
        this.logger = logger;
        this.debugDir = dataDir.resolve("bedrock-skins");
        this.apiKey = Optional.ofNullable(System.getenv("MINESKIN_API_KEY")).orElse("").trim();
        this.stateFile = Optional.ofNullable(System.getenv("BEDROCK_SKIN_STATE")).filter(v -> !v.isBlank()).map(Path::of).orElse(null);
        loadState();
        if (apiKey.isEmpty()) {
            logger.warn("MINESKIN_API_KEY no definida: las skins de Bedrock quedan en manos de Floodgate");
        }
        for (String entry : Optional.ofNullable(System.getenv("JAVA_ALIASES")).orElse("").split("[\\s,]+")) {
            String[] parts = entry.split("[=@]");
            if (parts.length != 3) {
                if (!entry.isBlank()) logger.warn("JAVA_ALIASES: entrada inválida '{}' (nombreJava=nombreBedrock@uuid)", entry);
                continue;
            }
            aliases.put(parts[0].toLowerCase(Locale.ROOT), new GameProfile(UUID.fromString(parts[2]), parts[1], List.of()));
            logger.info("Alias Java: {} entra como {} ({})", parts[0], parts[1], parts[2]);
        }
    }

    @Subscribe(priority = Short.MIN_VALUE) // el último: después de Floodgate (PostOrder.EARLY)
    public void onGameProfileRequest(GameProfileRequestEvent event, Continuation continuation) {
        GameProfile profile = event.getGameProfile();
        UUID uuid = profile.getId();
        // Floodgate: UUID 00000000-0000-0000-xxxx-xxxxxxxxxxxx con el XUID en los 64 bits bajos
        if (uuid.getMostSignificantBits() != 0) {
            GameProfile alias = aliases.get(profile.getName().toLowerCase(Locale.ROOT));
            if (alias != null) {
                GameProfile.Property skin = lastTexture.get(alias.getId());
                event.setGameProfile(skin == null ? alias : withTexture(alias, skin));
                logger.info("Alias Java: {} entra como {} ({}){}", profile.getName(), alias.getName(), alias.getId(),
                        skin == null ? "" : " con su skin de Bedrock");
            }
            continuation.resume();
            return;
        }
        if (apiKey.isEmpty()) {
            continuation.resume();
            return;
        }
        String xuid = Long.toUnsignedString(uuid.getLeastSignificantBits());
        CompletableFuture<GameProfile.Property> texture;
        try {
            texture = textureFor(profile.getName(), xuid);
        } catch (Exception e) {
            logger.warn("Skin Bedrock de {}: {}", profile.getName(), e.toString());
            continuation.resume();
            return;
        }
        if (texture == null) {
            continuation.resume();
            return;
        }
        texture.orTimeout(LOGIN_WAIT_SECONDS, TimeUnit.SECONDS).whenComplete((property, error) -> {
            if (error == null && property != null) {
                remember(uuid, property);
                event.setGameProfile(withTexture(event.getGameProfile(), property));
                logger.info("Skin Bedrock aplicada a {} al entrar", profile.getName());
            } else {
                logger.info("MineSkin aún no responde para {}; se aplicará en vivo", profile.getName());
                texture.thenAccept(p -> {
                    remember(uuid, p);
                    applyLive(uuid, p);
                });
            }
            continuation.resume();
        });
    }

    /** Skin que la tablet envió en esta conexión, firmada por MineSkin (null si no hay sesión de Geyser). */
    private CompletableFuture<GameProfile.Property> textureFor(String name, String xuid) throws Exception {
        Object client = geyserClientData(xuid);
        if (client == null) {
            logger.warn("Sin sesión de Geyser para {} (xuid {})", name, xuid);
            return null;
        }
        byte[] rgba = (byte[]) call(client, "getSkinData");
        int width = (int) call(client, "getSkinImageWidth");
        int height = (int) call(client, "getSkinImageHeight");
        boolean persona = (boolean) call(client, "isPersonaSkin");
        String patch = new String((byte[]) call(client, "getGeometryName"), StandardCharsets.UTF_8);
        String armSize = String.valueOf(call(client, "getArmSize"));
        boolean slim = "slim".equalsIgnoreCase(armSize) || patch.toLowerCase(Locale.ROOT).contains("slim");

        String geometry = geometry(patch);
        // Persona y geometrías propias usan un atlas con UVs según su geometría 3D, no la plantilla
        // clásica escalada: la conversión directa sale rota. Se guardan los datos para analizarlos.
        if (persona || !geometry.matches("geometry\\.humanoid(\\.custom)?(Slim)?")) {
            logger.info("Skin Bedrock de {}: {}x{}, persona={}, geometría={} → sin conversión (se guarda para análisis)",
                    name, width, height, persona, geometry);
            savePersonaDebug(name, rgba, width, height, patch, (byte[]) call(client, "getGeometryData"));
            return null;
        }
        byte[] png = toJavaPng(rgba, width, height);
        String hash = HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(png));
        logger.info("Skin Bedrock de {}: {}x{}, persona={}, brazos={}, geometría={}, sha256={}",
                name, width, height, persona, slim ? "slim" : "classic", geometry, hash.substring(0, 12));
        saveDebug(name, png);

        CompletableFuture<GameProfile.Property> cached = textures.get(hash);
        if (cached != null && !cached.isCompletedExceptionally()) {
            return cached;
        }
        CompletableFuture<GameProfile.Property> upload = upload(name, png, slim);
        textures.put(hash, upload);
        return upload;
    }

    private Object geyserClientData(String xuid) throws Exception {
        Object geyserPlugin = proxy.getPluginManager().getPlugin("geyser")
                .flatMap(c -> c.getInstance()).orElse(null);
        if (geyserPlugin == null) {
            return null;
        }
        ClassLoader loader = geyserPlugin.getClass().getClassLoader();
        Object api = Class.forName("org.geysermc.geyser.api.GeyserApi", true, loader).getMethod("api").invoke(null);
        for (Object connection : (List<?>) call(api, "onlineConnections")) {
            if (xuid.equals(call(connection, "xuid"))) {
                return call(connection, "getClientData");
            }
        }
        return null;
    }

    /**
     * Imagen RGBA de Bedrock → PNG de 64x64 (formato Java). Las skins HD (128/256) usan la misma
     * distribución escalada: se toma un píxel de cada bloque. 64x32 (formato antiguo) Java lo acepta tal cual.
     */
    static byte[] toJavaPng(byte[] rgba, int width, int height) throws Exception {
        if (width <= 0 || height <= 0 || rgba.length < width * height * 4 || width % 64 != 0
                || (height != width && height * 2 != width)) {
            throw new IllegalArgumentException("formato de skin no soportado: " + width + "x" + height);
        }
        int scale = width / 64;
        int outHeight = height / scale;
        BufferedImage image = new BufferedImage(64, outHeight, BufferedImage.TYPE_INT_ARGB);
        for (int y = 0; y < outHeight; y++) {
            for (int x = 0; x < 64; x++) {
                int i = ((y * scale) * width + (x * scale)) * 4;
                int argb = (rgba[i + 3] & 0xff) << 24 | (rgba[i] & 0xff) << 16 | (rgba[i + 1] & 0xff) << 8 | (rgba[i + 2] & 0xff);
                image.setRGB(x, y, argb);
            }
        }
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        ImageIO.write(image, "png", out);
        return out.toByteArray();
    }

    private CompletableFuture<GameProfile.Property> upload(String name, byte[] png, boolean slim) {
        String boundary = "----homelab" + UUID.randomUUID().toString().replace("-", "");
        ByteArrayOutputStream body = new ByteArrayOutputStream();
        writePart(body, boundary, "variant", slim ? "slim" : "classic");
        writePart(body, boundary, "visibility", "unlisted");
        writePart(body, boundary, "name", name.replaceAll("[^A-Za-z0-9_]", "").isEmpty()
                ? "bedrock" : name.replaceAll("[^A-Za-z0-9_]", ""));
        body.writeBytes(("--" + boundary + "\r\nContent-Disposition: form-data; name=\"file\"; filename=\"skin.png\"\r\n"
                + "Content-Type: image/png\r\n\r\n").getBytes(StandardCharsets.UTF_8));
        body.writeBytes(png);
        body.writeBytes(("\r\n--" + boundary + "--\r\n").getBytes(StandardCharsets.UTF_8));

        HttpRequest request = HttpRequest.newBuilder(URI.create(MINESKIN_URL))
                .timeout(Duration.ofSeconds(60))
                .header("Authorization", "Bearer " + apiKey)
                .header("User-Agent", USER_AGENT)
                .header("Content-Type", "multipart/form-data; boundary=" + boundary)
                .POST(HttpRequest.BodyPublishers.ofByteArray(body.toByteArray()))
                .build();
        return http.sendAsync(request, HttpResponse.BodyHandlers.ofString()).thenApply(response -> {
            if (response.statusCode() != 200) {
                throw new IllegalStateException("MineSkin HTTP " + response.statusCode() + ": "
                        + response.body().substring(0, Math.min(300, response.body().length())));
            }
            JsonObject skin = JsonParser.parseString(response.body()).getAsJsonObject().getAsJsonObject("skin");
            JsonObject data = skin.getAsJsonObject("texture").getAsJsonObject("data");
            logger.info("MineSkin: skin {} para {} (duplicada: {})", skin.get("uuid").getAsString(), name,
                    skin.has("duplicate") && skin.get("duplicate").getAsBoolean());
            return new GameProfile.Property("textures", data.get("value").getAsString(), data.get("signature").getAsString());
        }).whenComplete((p, e) -> {
            if (e != null) {
                logger.warn("MineSkin falló para {}: {}", name, e.getMessage());
            }
        });
    }

    private static void writePart(ByteArrayOutputStream body, String boundary, String name, String value) {
        body.writeBytes(("--" + boundary + "\r\nContent-Disposition: form-data; name=\"" + name + "\"\r\n\r\n"
                + value + "\r\n").getBytes(StandardCharsets.UTF_8));
    }

    private static GameProfile withTexture(GameProfile profile, GameProfile.Property texture) {
        List<GameProfile.Property> properties = new ArrayList<>(profile.getProperties());
        properties.removeIf(p -> p.getName().equals("textures"));
        properties.add(texture);
        return profile.withProperties(properties);
    }

    /** MineSkin respondió después del login: SkinsRestorer la aplica sin reconectar (proxy y servidor). */
    private void applyLive(UUID uuid, GameProfile.Property texture) {
        Optional<Player> player = proxy.getPlayer(uuid);
        if (player.isEmpty()) {
            return;
        }
        try {
            Object plugin = proxy.getPluginManager().getPlugin("skinsrestorer").flatMap(c -> c.getInstance()).orElseThrow();
            ClassLoader loader = plugin.getClass().getClassLoader();
            Object api = Class.forName("net.skinsrestorer.api.SkinsRestorerProvider", true, loader).getMethod("get").invoke(null);
            Method getApplier = Class.forName("net.skinsrestorer.api.SkinsRestorer", true, loader)
                    .getMethod("getSkinApplier", Class.class);
            Object applier = getApplier.invoke(api, Player.class);
            Class<?> skinProperty = Class.forName("net.skinsrestorer.api.property.SkinProperty", true, loader);
            Object property = skinProperty.getMethod("of", String.class, String.class)
                    .invoke(null, texture.getValue(), texture.getSignature());
            getApplier.getReturnType().getMethod("applySkin", Object.class, skinProperty).invoke(applier, player.get(), property);
            logger.info("Skin Bedrock aplicada en vivo a {}", player.get().getUsername());
        } catch (Exception e) {
            List<GameProfile.Property> properties = new ArrayList<>(player.get().getGameProfileProperties());
            properties.removeIf(p -> p.getName().equals("textures"));
            properties.add(texture);
            player.get().setGameProfileProperties(properties);
            logger.info("Skin Bedrock de {} lista; se verá al cambiar de servidor o reconectar ({})",
                    player.get().getUsername(), e.toString());
        }
    }

    private void remember(UUID uuid, GameProfile.Property texture) {
        GameProfile.Property previous = lastTexture.put(uuid, texture);
        if (stateFile == null || (previous != null && previous.getValue().equals(texture.getValue()))) {
            return;
        }
        JsonObject root = new JsonObject();
        lastTexture.forEach((id, t) -> {
            JsonObject o = new JsonObject();
            o.addProperty("value", t.getValue());
            o.addProperty("signature", t.getSignature());
            root.add(id.toString(), o);
        });
        try {
            Files.createDirectories(stateFile.getParent());
            Path tmp = stateFile.resolveSibling(stateFile.getFileName() + ".tmp");
            Files.writeString(tmp, root.toString());
            Files.move(tmp, stateFile, java.nio.file.StandardCopyOption.REPLACE_EXISTING, java.nio.file.StandardCopyOption.ATOMIC_MOVE);
        } catch (Exception e) {
            logger.warn("No se pudo guardar {}: {}", stateFile, e.toString());
        }
    }

    private void loadState() {
        if (stateFile == null || !Files.exists(stateFile)) {
            return;
        }
        try {
            JsonObject root = JsonParser.parseString(Files.readString(stateFile)).getAsJsonObject();
            root.entrySet().forEach(e -> {
                JsonObject o = e.getValue().getAsJsonObject();
                lastTexture.put(UUID.fromString(e.getKey()),
                        new GameProfile.Property("textures", o.get("value").getAsString(), o.get("signature").getAsString()));
            });
            logger.info("Skins Bedrock guardadas: {} ({})", lastTexture.size(), stateFile);
        } catch (Exception e) {
            logger.warn("No se pudo leer {}: {}", stateFile, e.toString());
        }
    }

    /** Textura completa + geometría de una skin Persona, en el volumen persistente (/state/debug). */
    private void savePersonaDebug(String name, byte[] rgba, int width, int height, String patch, byte[] geometryData) {
        if (stateFile == null) {
            return;
        }
        try {
            Path dir = stateFile.resolveSibling("debug");
            Files.createDirectories(dir);
            String base = name.replaceAll("[^A-Za-z0-9_.-]", "_");
            BufferedImage image = new BufferedImage(width, height, BufferedImage.TYPE_INT_ARGB);
            for (int i = 0; i < width * height; i++) {
                int o = i * 4;
                image.setRGB(i % width, i / width, (rgba[o + 3] & 0xff) << 24 | (rgba[o] & 0xff) << 16 | (rgba[o + 1] & 0xff) << 8 | (rgba[o + 2] & 0xff));
            }
            ImageIO.write(image, "png", dir.resolve(base + ".atlas.png").toFile());
            Files.writeString(dir.resolve(base + ".resource-patch.json"), patch);
            Files.write(dir.resolve(base + ".geometry.json"), geometryData == null ? new byte[0] : geometryData);
            logger.info("Datos de skin Persona de {} guardados en {}", name, dir);
        } catch (Exception e) {
            logger.warn("No se pudieron guardar los datos de skin de {}: {}", name, e.toString());
        }
    }

    private void saveDebug(String name, byte[] png) {
        try {
            Files.createDirectories(debugDir);
            Files.write(debugDir.resolve(name.replaceAll("[^A-Za-z0-9_.-]", "_") + ".png"), png);
        } catch (Exception e) {
            logger.debug("No se pudo guardar la skin de {}: {}", name, e.toString());
        }
    }

    private static String geometry(String patch) {
        try {
            return JsonParser.parseString(patch).getAsJsonObject().getAsJsonObject("geometry").get("default").getAsString();
        } catch (Exception e) {
            return "?";
        }
    }

    private static Object call(Object target, String method) throws Exception {
        Method m = findMethod(target.getClass(), method);
        m.setAccessible(true);
        return m.invoke(target);
    }

    private static Method findMethod(Class<?> type, String name) throws NoSuchMethodException {
        for (Class<?> c = type; c != null; c = c.getSuperclass()) {
            for (Method m : c.getDeclaredMethods()) {
                if (m.getName().equals(name) && m.getParameterCount() == 0) {
                    return m;
                }
            }
        }
        return type.getMethod(name);
    }
}
