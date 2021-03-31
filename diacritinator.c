#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

int m = 0x10FF80;
int shift = 0x80;

int bufoff = 0;
int bufsz = 0;
int BUFSZ = 2048;
char buf[BUFSZ];

typedef struct {
    int n;
    // moze byc wieksze od int? statyczne czy dynamiczne
    int coeffs[];
} poly_t;

poly_t txt_to_poly_t(int argc, char *argv[]) {
    poly_t ret;
    ret.n = argc - 1;
    ret.coeffs = malloc(ret.n * sizeof *ret.coeffs);
    for (int i = 1; i < argc; ++i) {
        ret.coeffs[ret.n - i] = strtol(argv[i]); // co jak -, 0, albo inny blad?
        if (errno == ERANGE) {
            fprintf(stderr, "Zły wykładnik wielomianu.\n");
            exit(1);
        }
    }
    return ret;
}

int get_val(poly_t poly, int x) {
    int val = 0, power = 1;
    for (int i = 0; i < poly.n; ++i, power *= x) {
        val += (power * coeffs[i]) % m;
        val %= m;
    }
    return val;
}

int get_char() {
  if (bufoff >= bufsz) {
    bufsz = read(STDIN_FILENO, buf, BUFSIZE);
    if (bufsz == 0) return -1;
    if (bufsz < 0) abort();
    bufoff = 0;
  }
  return buf[bufoff++];
}

int transform(poly_t poly) {
    int c1;
    bool ok = true;
    while (-1 != (c1 = get_char())) {
        int x = 0; // ??

        if ((c1 & (1 << 7)) >> 7 == 0) {
            // We have 1 byte UTF-8
            // TODO get unicode from those xxxxxx
        } else {
            int c2 = get_char();
            if ((c1 & (1 << 6)) >> 6 != 1 || c2 == -1 || (c2 & (1 << 7)) >> 7 != 1 || (c2 & (1 << 6)) >> 6 != 0) {
                ok = false;
                break;
            }
            if ((c1 & (1 << 5)) >> 5 == 0) {
                // We have 2 byte UTF-8
            } else {
                int c3 = get_char();
                if (c3 == -1 || (c3 & (1 << 7)) >> 7 != 1 || (c3 & (1 << 6)) >> 6 != 0) {
                    ok = false;
                    break;
                }
                if ((c1 & (1 << 4)) >> 4 == 0) {
                    // We have 3 byte UTF-8
                } else {
                    int c4 = get_char();
                    if ((c1 & (1 << 3)) >> 3 != 0 || c4 == -1 || (c3 & (1 << 7)) >> 7 != 1 || (c3 & (1 << 6)) >> 6 != 0) {
                        ok = false;
                        break;
                    }
                    // We have 4 byte UTF-8
                }
            }
        }
        // zamienic na wypisanie byte'ow mając unicode
        printf("%c", x < shift ? x : get_val(poly, x - shift) + shift);
    }

    return ok ? 0 : 1;
}

int main(int argc, char *argv[]) {
    int ret = transform(txt_to_poly_t(argc, argv));
    if (ret == 1)
        fprintf(stderr, "Zły wczytany znak.\n");
    return ret;
}
