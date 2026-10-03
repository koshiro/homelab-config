package cl.danielriquelme.homelab;

import com.google.inject.Inject;
import com.velocitypowered.api.event.Subscribe;
import com.velocitypowered.api.event.command.CommandExecuteEvent;
import com.velocitypowered.api.event.proxy.ProxyInitializeEvent;
import com.velocitypowered.api.plugin.annotation.DataDirectory;
import com.velocitypowered.api.proxy.Player;
import com.velocitypowered.api.proxy.ProxyServer;
import java.nio.file.Path;
import java.util.Locale;
import java.util.Set;
import org.slf4j.Logger;

/**
 * /lobby (y /hub) transparente en toda la red.
 *
 * Si el jugador está en otro servidor (p. ej. un Parkour Spiral), el proxy lo devuelve al
 * servidor principal, donde Multiverse lo deja en el mundo lobby (join-destination).
 * Si ya está en el principal, el comando sigue su curso y lo resuelve el alias /lobby del
 * propio Paper (mvtp w:lobby), así funciona igual desde OneBlock o el mundo familiar.
 *
 * También registra {@link BedrockSkins} (skin actual de Bedrock vista desde Java).
 */
public class LobbyPlugin {
    private static final String PRINCIPAL = "principal";
    private static final Set<String> COMMANDS = Set.of("lobby", "hub");

    private final ProxyServer proxy;
    private final Logger logger;

    private final Path dataDir;

    @Inject
    public LobbyPlugin(ProxyServer proxy, Logger logger, @DataDirectory Path dataDir) {
        this.proxy = proxy;
        this.logger = logger;
        this.dataDir = dataDir;
    }

    @Subscribe
    public void onInit(ProxyInitializeEvent event) {
        proxy.getEventManager().register(this, new BedrockSkins(proxy, logger, dataDir));
    }

    @Subscribe
    public void onCommand(CommandExecuteEvent event) {
        if (!(event.getCommandSource() instanceof Player player)) {
            return;
        }
        String command = event.getCommand().trim().toLowerCase(Locale.ROOT);
        if (!COMMANDS.contains(command)) {
            return;
        }
        String current = player.getCurrentServer()
                .map(s -> s.getServerInfo().getName())
                .orElse("");
        if (current.equalsIgnoreCase(PRINCIPAL)) {
            return;
        }
        event.setResult(CommandExecuteEvent.CommandResult.denied());
        proxy.getServer(PRINCIPAL).ifPresentOrElse(
                server -> player.createConnectionRequest(server).fireAndForget(),
                () -> logger.warn("Servidor '{}' no registrado en velocity.toml", PRINCIPAL));
    }
}
