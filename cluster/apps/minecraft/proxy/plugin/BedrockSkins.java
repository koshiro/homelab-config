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

    public BedrockSkins(ProxyServer proxy, Logger logger, Path dataDir) {
        this.proxy = proxy;
        this.logger = logger;
        this.debugDir = dataDir.resolve("bedrock-skins");
        this.apiKey = Optional.ofNullable(System.getenv("MINESKIN_API_KEY")).orElse("").trim();
        if (apiKey.isEmpty()) {
            logger.warn("MINESKIN_API_KEY no definida: las skins de Bedrock quedan en manos de Floodgate");
        }
    }

    @Subscribe(priority = Short.MIN_VALUE) // el último: después de Floodgate (PostOrder.EARLY)
    public void onGameProfileRequest(GameProfileRequestEvent event, Continuation continuation) {
        GameProfile profile = event.getGameProfile();
        UUID uuid = profile.getId();
        // Floodgate: UUID 00000000-0000-0000-xxxx-xxxxxxxxxxxx con el XUID en los 64 bits bajos
        if (apiKey.isEmpty() || uuid.getMostSignificantBits() != 0) {
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
                event.setGameProfile(withTexture(event.getGameProfile(), property));
                logger.info("Skin Bedrock aplicada a {} al entrar", profile.getName());
            } else {
                logger.info("MineSkin aún no responde para {}; se aplicará en vivo", profile.getName());
                texture.thenAccept(p -> applyLive(uuid, p));
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

        byte[] png = toJavaPng(rgba, width, height);
        String hash = HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(png));
        logger.info("Skin Bedrock de {}: {}x{}, persona={}, brazos={}, geometría={}, sha256={}",
                name, width, height, persona, slim ? "slim" : "classic", geometry(patch), hash.substring(0, 12));
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
