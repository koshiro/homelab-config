# Configuración de Correo en Overseerr con iCloud Mail

## Problema Identificado
La configuración de red de Overseerr no incluía los puertos necesarios para SMTP, impidiendo el envío de correos electrónicos.

## Solución Aplicada

### 1. NetworkPolicy Actualizada
Se han añadido los siguientes puertos a la NetworkPolicy de egress (`cluster/overseerr/networkpolicy-egress.yml`):

```yaml
# SMTP para envío de correos (iCloud Mail)
- to:
  - ipBlock:
      cidr: 0.0.0.0/0
  ports:
  - protocol: TCP
    port: 587  # SMTP con STARTTLS
  - protocol: TCP
    port: 465  # SMTP con SSL/TLS
  - protocol: TCP
    port: 993  # IMAP con SSL/TLS (por si se necesita)
```

### 2. Configuración en Overseerr
Para configurar el correo en la interfaz web de Overseerr:

#### Parámetros de Configuración:
- **Servidor SMTP**: `smtp.mail.me.com`
- **Puerto SMTP**: `587` (recomendado con STARTTLS) o `465` (con SSL/TLS)
- **Método de cifrado**: 
  - `STARTTLS` para puerto 587
  - `SSL/TLS` para puerto 465
- **Nombre de usuario**: Tu dirección de correo de iCloud (ej: `usuario@icloud.com`)
- **Contraseña**: **Contraseña específica de aplicación** (NO tu contraseña normal de iCloud)

#### Generar Contraseña Específica de Aplicación para iCloud:

1. Ve a [appleid.apple.com](https://appleid.apple.com/)
2. Inicia sesión con tu cuenta de Apple
3. Ve a la sección **"Seguridad"**
4. En **"Contraseñas específicas de la aplicación"**, selecciona **"Generar contraseña"**
5. Ingresa un nombre descriptivo (ej: "Overseerr Email")
6. Haz clic en **"Crear"**
7. **Copia la contraseña generada** (formato: xxxx-xxxx-xxxx-xxxx)
8. Usa esta contraseña en la configuración de Overseerr

### 3. Verificación
- La resolución DNS para `smtp.mail.me.com` funciona correctamente
- Los puertos necesarios están ahora permitidos en la NetworkPolicy
- Resuelve a la IP: `17.57.154.37` (a través de `smtp.mail.me.com.akadns.net`)

### 4. Aplicar Cambios
Para aplicar los cambios en el cluster:

```bash
kubectl apply -f cluster/overseerr/networkpolicy-egress.yml
```

### 5. Probar Configuración
1. Accede a la interfaz web de Overseerr
2. Ve a Configuración → Notificaciones → Email
3. Configura los parámetros mencionados arriba
4. Usa la función de "Enviar correo de prueba"
5. Verifica que el correo llegue correctamente

## Notas Importantes
- **NUNCA** uses tu contraseña normal de iCloud para aplicaciones de terceros
- La contraseña específica de aplicación es obligatoria si tienes la verificación en dos pasos habilitada
- Si cambias tu contraseña de iCloud, las contraseñas específicas de aplicación siguen siendo válidas
- Puedes revocar contraseñas específicas de aplicación en cualquier momento desde tu cuenta de Apple

## Troubleshooting
Si aún tienes problemas:
1. Verifica que la contraseña específica de aplicación sea correcta
2. Comprueba los logs de Overseerr: `kubectl logs -n overseerr deployment/overseerr`
3. Verifica conectividad desde el pod: `kubectl exec -n overseerr deployment/overseerr -- telnet smtp.mail.me.com 587`
