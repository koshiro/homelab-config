package cl.danielriquelme.homelab;

import com.velocitypowered.api.event.ResultedEvent;
import com.velocitypowered.api.event.Subscribe;
import com.velocitypowered.api.event.connection.PreLoginEvent;
import com.velocitypowered.api.event.proxy.ProxyPingEvent;
import com.velocitypowered.api.proxy.InboundConnection;
import java.util.Arrays;
import java.util.Locale;
import java.util.Optional;
import java.util.Set;
import java.util.stream.Collectors;
import net.kyori.adventure.text.Component;
import org.slf4j.Logger;

/**
 * Descarta a quien no se conecta con el dominio del servidor.
 *
 * Los escáneres de IPv4 (matscan y similares) prueban el 25565 de cualquier IP y en el handshake
 * mandan la IP o un nombre propio ("matscan"), nunca minecraft.danielriquelme.cl. Sin respuesta al
 * ping no quedan en sus listas, y el login se corta antes del principal (no llega al whitelist ni
 * al bot de Telegram).
 *
 * Se aceptan además los hosts locales: Geyser (direct connection) entra con la dirección del
 * propio proxy, no con la que usó el jugador Bedrock.
 */
public class HostnameFilter {
    private static final Set<String> LOCAL_HOSTS = Set.of("127.0.0.1", "0.0.0.0", "localhost", "::1");

    private final Logger logger;
    private final Set<String> allowed;

    public HostnameFilter(Logger logger) {
        this.logger = logger;
        String env = System.getenv().getOrDefault("ALLOWED_HOSTS", "minecraft.danielriquelme.cl");
        this.allowed = Arrays.stream(env.split(","))
                .map(h -> h.trim().toLowerCase(Locale.ROOT))
                .filter(h -> !h.isEmpty())
                .collect(Collectors.toUnmodifiableSet());
        logger.info("Filtro de hostname activo: {}", allowed);
    }

    @Subscribe
    public void onPing(ProxyPingEvent event) {
        rejectedHost(event.getConnection()).ifPresent(host -> {
            logger.info("Ping descartado de {} (host '{}')", event.getConnection().getRemoteAddress(), host);
            event.setResult(ResultedEvent.GenericResult.denied());
        });
    }

    @Subscribe
    public void onPreLogin(PreLoginEvent event) {
        rejectedHost(event.getConnection()).ifPresent(host -> {
            logger.info("Login descartado de {} como {} (host '{}')",
                    event.getConnection().getRemoteAddress(), event.getUsername(), host);
            event.setResult(PreLoginEvent.PreLoginComponentResult.denied(Component.text("Conexión no permitida.")));
        });
    }

    /** Host del handshake si no está permitido; vacío si se acepta (o si no hay handshake que juzgar). */
    private Optional<String> rejectedHost(InboundConnection connection) {
        return connection.getVirtualHost()
                .map(address -> address.getHostString().toLowerCase(Locale.ROOT))
                .filter(host -> !allowed.contains(host) && !LOCAL_HOSTS.contains(host));
    }
}
