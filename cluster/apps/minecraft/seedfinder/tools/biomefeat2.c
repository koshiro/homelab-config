// Biomas por semilla (Minecraft Java 26.2) para el puntaje v2: distancia desde el origen al bioma más cercano
// de cada tipo, en superficie y en cuevas. Lee semillas por stdin (una por línea), escribe una línea JSON.
// Usa el cubiomes adaptado a 26.2 que trae MCSeedFinder (vendor/cubiomes).
//   superficie: muestreo cada STEP bloques a Y=256 (por encima del terreno => bioma de superficie, no de cueva)
//   cuevas:     muestreo cada USTEP bloques a varias alturas (sulfur, lush, dripstone, deep_dark)
//   land200:    fracción de tierra (sin océano ni río) a menos de 200 m del origen
#include "generator.h"
#include "biomes.h"
#include "util.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#define R_SURF 800
#define STEP 16
#define R_LAND 200
#define R_CAVE 800
#define USTEP 24

static int is_ocean_or_river(int b) {
    return isOceanic(b) || b == river || b == frozen_river;
}

int main(void) {
    Generator g;
    setupGenerator(&g, MC_26_2, 0);
    char line[64];
    static const int ys[] = {-40, -8, 24};  // alturas de bloque para biomas de cueva
    static const int caves[] = {sulfur_caves, lush_caves, dripstone_caves, deep_dark};
    while (fgets(line, sizeof line, stdin)) {
        char *end;
        long long s = strtoll(line, &end, 10);
        if (end == line) continue;
        applySeed(&g, DIM_OVERWORLD, (uint64_t)s);
        double surf[256], cave[256];
        for (int i = 0; i < 256; i++) surf[i] = cave[i] = -1;
        int n_land = 0, land = 0;
        for (int x = -R_SURF; x <= R_SURF; x += STEP)
            for (int z = -R_SURF; z <= R_SURF; z += STEP) {
                double d = sqrt((double)x * x + (double)z * z);
                if (d > R_SURF) continue;
                int b = getBiomeAt(&g, 4, x >> 2, 256 >> 2, z >> 2);
                if (b < 0 || b > 255) continue;
                if (surf[b] < 0 || d < surf[b]) surf[b] = d;
                if (d <= R_LAND) { n_land++; if (!is_ocean_or_river(b)) land++; }
            }
        for (int x = -R_CAVE; x <= R_CAVE; x += USTEP)
            for (int z = -R_CAVE; z <= R_CAVE; z += USTEP) {
                double d = sqrt((double)x * x + (double)z * z);
                if (d > R_CAVE) continue;
                for (int i = 0; i < 3; i++) {
                    int b = getBiomeAt(&g, 4, x >> 2, ys[i] >> 2, z >> 2);
                    if (b >= 0 && b < 256 && (cave[b] < 0 || d < cave[b])) cave[b] = d;
                }
            }
        printf("{\"seed\":%lld,\"land200\":%.3f,\"surf\":{", s, n_land ? (double)land / n_land : 0);
        int first = 1;
        for (int b = 0; b < 256; b++) if (surf[b] >= 0) {
            printf("%s\"%s\":%.0f", first ? "" : ",", biome2str(MC_26_2, b), surf[b]); first = 0;
        }
        printf("},\"cave\":{");
        first = 1;
        for (int i = 0; i < 4; i++) if (cave[caves[i]] >= 0) {
            printf("%s\"%s\":%.0f", first ? "" : ",", biome2str(MC_26_2, caves[i]), cave[caves[i]]); first = 0;
        }
        printf("}}\n");
        fflush(stdout);
    }
    return 0;
}
