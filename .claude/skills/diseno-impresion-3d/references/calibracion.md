# Calibración de esta máquina

Lo medido aquí manda sobre cualquier tabla. Hoy no hay ningún valor medido: todas las columnas de boquilla 0.5 de las
otras referencias son inferencia. Rehacer al cambiar boquilla, marca de filamento, número de paredes o pressure advance.

## Cuatro impresiones que cierran casi toda la incertidumbre

Calibrar flujo y pressure advance antes, y congelar el perfil.

1. **Torre de voladizos**, por material: 40°, 45°, 50°, 55°, 60°, 65°. Anotar el último ángulo limpio.
2. **Escalera de agujeros y pines**, por material: nominal −0.2 a +0.5 en pasos de 0.1, a los diámetros reales, un juego
   con eje vertical y otro horizontal, separados 15 mm o más. Medir con el herraje real o vástagos de broca. Anotar primer
   libre, primer ajustado y primer a presión.
3. **Peine de huecos** de 0.20 a 0.60 por lado: desde qué hueco queda separado.
4. **Barras de ABS+** de 80, 120 y 160 mm, sin cerramiento: desde qué largo se despega.

## Valores medidos

Una fila por medición. `offset` es lo que hay que sumar al diámetro nominal en CAD.

| Fecha | Material y marca | Boquilla, línea, capa | Rasgo | Orientación | Medido | Regla que corrige |
|-------|------------------|-----------------------|-------|-------------|--------|-------------------|

## Piezas de referencia

- `boton-ble` (2026-11-02, PETG, capa 0.11): carcasa, tapa y embellecedor, en `~/Documents/ble-button/`. Falta anotar cómo
  ajustaron las holguras (`cell_clr` 0.2, `cap_gap` 0.34, `cap_bore` 4.05 sobre émbolo de 4.0).
