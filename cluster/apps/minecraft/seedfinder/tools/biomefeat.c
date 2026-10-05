// Características de biomas por semilla (Minecraft Java 26.2) para el ranking de semillas.
// Lee semillas por stdin (una por línea) y escribe una línea JSON por semilla.
// Usa el cubiomes adaptado a 26.2 que trae MCSeedFinder (vendor/cubiomes).
//   superficie: muestreo cada STEP bloques a Y=256 (por encima del terreno => bioma de superficie, no de cueva)
//   subsuelo:   sulfur_caves y deep_dark, muestreo cada USTEP bloques a varias alturas
#include "generator.h"
#include "biomes.h"
#include "util.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define R_NEAR 300
#define R_FAR 600
#define STEP 16
#define R_UNDER 1000
#define USTEP 32

static int is_ocean_or_river(int b) {
    return isOceanic(b) || b == river || b == frozen_river;
}

int main(void) {
    Generator g;
    setupGenerator(&g, MC_26_2, 0);
    char line[64];
    static const int ys[] = {-40, -8, 24};  // alturas de bloque para biomas de cueva
    while (fgets(line, sizeof line, stdin)) {
        char *end;
        long long s = strtoll(line, &end, 10);
        if (end == line) continue;
        applySeed(&g, DIM_OVERWORLD, (uint64_t)s);
        int cnt_near[256] = {0}, cnt_far[256] = {0}, n_near = 0, n_far = 0, land_near = 0;
        for (int x = -R_FAR; x <= R_FAR; x += STEP)
            for (int z = -R_FAR; z <= R_FAR; z += STEP) {
                int d2 = x * x + z * z;
                if (d2 > R_FAR * R_FAR) continue;
                int b = getBiomeAt(&g, 4, x >> 2, 256 >> 2, z >> 2);
                if (b < 0 || b > 255) continue;
                cnt_far[b]++; n_far++;
                if (d2 <= R_NEAR * R_NEAR) { cnt_near[b]++; n_near++; if (!is_ocean_or_river(b)) land_near++; }
            }
        int distinct_near = 0, distinct_far = 0; double h = 0;
        for (int b = 0; b < 256; b++) {
            if (cnt_near[b]) distinct_near++;
            if (cnt_far[b]) { distinct_far++; double p = (double)cnt_far[b] / n_far; h -= p * log(p); }
        }
        double sulfur = -1, deep_dark_d = -1;
        for (int x = -R_UNDER; x <= R_UNDER; x += USTEP)
            for (int z = -R_UNDER; z <= R_UNDER; z += USTEP) {
                double d = sqrt((double)x * x + (double)z * z);
                if (d > R_UNDER) continue;
                if ((sulfur >= 0 && d >= sulfur) && (deep_dark_d >= 0 && d >= deep_dark_d)) continue;
                for (int i = 0; i < 3; i++) {
                    int b = getBiomeAt(&g, 4, x >> 2, ys[i] >> 2, z >> 2);
                    if (b == sulfur_caves && (sulfur < 0 || d < sulfur)) sulfur = d;
                    if (b == deep_dark && (deep_dark_d < 0 || d < deep_dark_d)) deep_dark_d = d;
                }
            }
        printf("{\"seed\":%lld,\"biomes_near\":%d,\"biomes_far\":%d,\"entropy_far\":%.4f,\"land_near\":%.3f,"
               "\"sulfur_dist\":%.0f,\"deep_dark_dist\":%.0f,\"biome_hist_far\":{",
               s, distinct_near, distinct_far, h, n_near ? (double)land_near / n_near : 0, sulfur, deep_dark_d);
        int first = 1;
        for (int b = 0; b < 256; b++) if (cnt_far[b]) {
            printf("%s\"%s\":%d", first ? "" : ",", biome2str(MC_26_2, b), cnt_far[b]); first = 0;
        }
        printf("}}\n");
        fflush(stdout);
    }
    return 0;
}
