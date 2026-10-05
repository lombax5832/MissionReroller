/* Research only (docs/NATIVE_SOLVER_RESEARCH.md): the seed solver's job
   loop (src/seed_solver_chain.lua job(), src/seed_solver_math.lua) in C, run
   on jobs written by dump_jobs.lua, to measure what native code would gain
   over LuaJIT. Checks every job's candidates against the LuaJIT run.

   cl /O2 /nologo solver_bench.c
   solver_bench <jobs.txt> [threads] [repeat]  */
#include <intrin.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <windows.h>

typedef uint64_t u64;
typedef int64_t i64;
#define MAXP 128
static u64 A[MAXP + 1], C[MAXP + 1];
static const double M32 = 4294967296.0;

static inline u64 output(u64 s, int p) { return (A[p] * s + C[p]) >> 32; }

/* Least x >= 0 with lo <= a*x mod m <= hi, m == 0 standing for 2^64;
   returns 0 and sets *ok=0 when none (seed_solver_math.lua first). */
static u64 first(u64 a, u64 m, u64 lo, u64 hi, int *ok) {
    *ok = 1;
    if (m) a %= m;
    if (lo == 0) return 0;
    if (a == 0) { *ok = 0; return 0; }
    if ((m == 0 && a > 0x8000000000000000ULL) || (m && a > m - a)) return first(m - a, m, m - hi, m - lo, ok);
    u64 k = lo / a + (lo % a ? 1 : 0);
    if (k <= hi / a) return k;
    u64 s = lo % a;
    u64 rest = m == 0 ? (0 - a) % a : m % a;
    u64 y = first((a - rest) % a, a, s, s + (hi - lo), ok);
    if (!*ok) return 0;
    u64 high, low;
    if (m == 0) { high = y; low = 0; } else low = _umul128(m, y, &high);
    u64 add = lo + (a - 1);
    if (add < lo) high++;
    u64 sum = low + add;
    if (sum < low) high++;
    u64 r;
    return _udiv128(high, sum, a, &r);
}

typedef struct {
    int all; u64 a, c, base, width, da, db, d12; int fa, fb; i64 na, nb, n12;
} Walk;
static void walk_init(Walk *w, int p, u64 lo, u64 hi) {
    int ok;
    w->a = A[p]; w->c = C[p]; w->base = lo << 32;
    u64 count = hi - lo + 1;
    w->all = count == (1ULL << 32);
    if (w->all) return;
    w->width = count << 32;
    u64 q1 = first(w->a, 0, 1, w->width - 1, &ok);
    u64 q2 = first(w->a, 0, 0 - w->width + 1, 0 - 1ULL, &ok);
    u64 d1 = w->a * q1, d2 = 0 - w->a * q2;
    u64 qa = q1, da = d1, qb = q2, db = d2; int fa = 1, fb = 0;
    if (q2 < q1) { qa = q2; da = d2; fa = 0; qb = q1; db = d1; fb = 1; }
    w->da = da; w->db = db; w->fa = fa; w->fb = fb;
    w->na = (i64)qa; w->nb = (i64)qb; w->n12 = (i64)(q1 + q2); w->d12 = d1 - d2;
}
/* First solution at or after s; returns 0 when none. */
static int walk_start(const Walk *w, i64 *s, u64 *off) {
    if (w->all) { *off = w->a * (u64)*s + w->c; return 1; }
    u64 left = w->base - w->c - w->a * (u64)*s, t = 0;
    if (left != 0 && left <= 0 - w->width) {
        int ok; t = first(w->a, 0, left, left + (w->width - 1), &ok);
        if (!ok) return 0;
    }
    *s += (i64)t; *off = w->a * (u64)*s + w->c - w->base;
    return 1;
}
static inline void walk_advance(const Walk *w, i64 *s, u64 *off) {
    if (w->all) { *s += 1; *off += w->a; return; }
    u64 o = *off;
    if (w->fa) { u64 n = o + w->da; if (n >= o && n < w->width) { *s += w->na; *off = n; return; } }
    else if (o >= w->da) { *s += w->na; *off = o - w->da; return; }
    if (w->fb) { u64 n = o + w->db; if (n >= o && n < w->width) { *s += w->nb; *off = n; return; } }
    else if (o >= w->db) { *s += w->nb; *off = o - w->db; return; }
    *s += w->n12; *off = o + w->d12;
}

typedef struct { i64 us, vs; double p, q, r, z, ri, rj; u64 a, c; int ready; } Inverter;
static Inverter inverters[MAXP + 1];
static double norm(i64 s, i64 t) { double x = (double)s, y = (double)t; return x * x + y * y; }
static Inverter *inverter(int p) {
    Inverter *v = &inverters[p];
    if (v->ready) return v;
    u64 a = A[p];
    i64 us = 1, ut = (i64)a;
    double k = floor(M32 * M32 / (double)ut + 0.5);
    i64 vs = -(i64)k, vt = (i64)(a * (u64)vs);
    for (int it = 0; it < 200; it++) {
        if (norm(us, ut) > norm(vs, vt)) { i64 t = us; us = vs; vs = t; t = ut; ut = vt; vt = t; }
        double q = floor(((double)us * (double)vs + (double)ut * (double)vt) / norm(us, ut) + 0.5);
        if (q == 0) break;
        i64 kq = (i64)q;
        vs = vs - kq * us; vt = vt - kq * ut;
        if (norm(vs, vt) >= norm(us, ut)) break;
    }
    double fus = (double)us, fut = (double)ut, fvs = (double)vs, fvt = (double)vt;
    double det = fus * fvt - fut * fvs;
    v->p = fvt / det; v->q = -fut / det; v->r = -fvs / det; v->z = fus / det;
    double half = M32 / 2;
    v->ri = fabs(v->p) * half + fabs(v->r) * half + 1;
    v->rj = fabs(v->q) * half + fabs(v->z) * half + 1;
    v->us = us; v->vs = vs; v->a = a; v->c = C[p];
    v->ready = 1;
    return v;
}
static int invert(const Inverter *v, u64 value, u64 *out) {
    int n = 0;
    u64 target = (value << 32) - v->c;
    double half = M32 / 2, cs = half, ct = (double)target + half;
    double ci = cs * v->p + ct * v->r, cj = cs * v->q + ct * v->z;
    i64 i0 = (i64)floor(ci - v->ri), i1 = (i64)ceil(ci + v->ri);
    i64 j0 = (i64)floor(cj - v->rj), j1 = (i64)ceil(cj + v->rj);
    for (i64 i = i0; i <= i1; i++) {
        i64 iu = i * v->us;
        for (i64 j = j0; j <= j1; j++) {
            u64 s = (u64)(iu + j * v->vs);
            if (s < (1ULL << 32) && ((v->a * s + v->c) >> 32) == value) out[n++] = s;
        }
    }
    return n;
}

/* A mission constraint's decision tree, in flat arrays. */
typedef struct {
    int nslots, slot_pos[64];
    int nnodes;
    int *efirst, *elast, *eslot, *echild; u64 *elo, *ehi;
    int *accept, *sfirst, *slast, *mfirst, *mlast; u64 *mmod, *mlo, *mhi;
} Tree;
typedef struct { int mission, position, has_lo; u64 lo, hi; Tree *tree; } Constraint;
typedef struct {
    u64 s0; int seed_position, root_kind, root_position, root_step; u64 root_lo, root_hi;
    int nc; Constraint *c;
    long long lua_steps; int lua_n; u64 *lua_seeds; double lua_seconds;
    long long steps; int n, cap; u64 *seeds; double seconds;
} Job;
static int planet;

static FILE *in;
static double num(void) {
    char tok[64];
    for (;;) {
        if (fscanf(in, "%63s", tok) != 1) { fprintf(stderr, "unexpected end\n"); exit(1); }
        if (tok[0] == '#') { double t; fscanf(in, "%63s %lf", tok, &t); continue; }
        return atof(tok);
    }
}
static u64 unum(void) { return (u64)num(); }

static Tree *read_tree(void) {
    Tree *t = calloc(1, sizeof *t);
    int nn = (int)num(), cap = 4096;
    t->nnodes = nn;
#define ARR(name, type, n) t->name = calloc(n, sizeof(type))
    ARR(efirst, int, nn); ARR(elast, int, nn); ARR(accept, int, nn); ARR(sfirst, int, nn); ARR(slast, int, nn);
    ARR(eslot, int, cap); ARR(echild, int, cap); ARR(elo, u64, cap); ARR(ehi, u64, cap);
    ARR(mfirst, int, cap); ARR(mlast, int, cap); ARR(mmod, u64, cap); ARR(mlo, u64, cap); ARR(mhi, u64, cap);
    int e = 0, set = 0, k = 0;
    for (int i = 0; i < nn; i++) {
        int ne = (int)num();
        t->efirst[i] = e;
        for (int x = 0; x < ne; x++) {
            int pos = (int)num(); u64 lo = unum(), hi = unum(); int child = (int)num();
            int s = -1;
            for (int y = 0; y < t->nslots; y++) if (t->slot_pos[y] == pos) s = y;
            if (s < 0) { s = t->nslots++; t->slot_pos[s] = pos; }
            t->eslot[e] = s; t->elo[e] = lo; t->ehi[e] = hi; t->echild[e] = child; e++;
        }
        t->elast[i] = e;
        int nends = (int)num();
        t->sfirst[i] = set;
        for (int x = 0; x < nends; x++) {
            int nm = (int)num();
            if (nm == 0) t->accept[i] = 1;
            t->mfirst[set] = k;
            for (int y = 0; y < nm; y++) { t->mmod[k] = unum(); t->mlo[k] = unum(); t->mhi[k] = unum(); k++; }
            t->mlast[set] = k; set++;
        }
        t->slast[i] = set;
    }
    if (e > cap || k > cap || set > cap) { fprintf(stderr, "tree too large\n"); exit(1); }
    return t;
}

static int tree_ok(const Tree *t, u64 m) {
    u64 cache[64]; unsigned char have[64] = {0};
    int stack[512], sp = 0;
    u64 state1 = A[1] * m + C[1];
    stack[sp++] = 0;
    while (sp > 0) {
        int node = stack[--sp];
        if (t->accept[node]) return 1;
        for (int j = t->sfirst[node]; j < t->slast[node]; j++) {
            int ok = 1;
            for (int x = t->mfirst[j]; x < t->mlast[j]; x++) {
                u64 v = state1 % t->mmod[x];
                if (v < t->mlo[x] || v > t->mhi[x]) { ok = 0; break; }
            }
            if (ok) return 1;
        }
        for (int x = t->efirst[node]; x < t->elast[node]; x++) {
            int s = t->eslot[x];
            if (!have[s]) { cache[s] = output(m, t->slot_pos[s]); have[s] = 1; }
            u64 o = cache[s];
            if (o >= t->elo[x] && o <= t->ehi[x]) stack[sp++] = t->echild[x];
        }
    }
    return 0;
}

static int path_ok(const Job *j, u64 y) {
    for (int i = 0; i < j->nc; i++) {
        const Constraint *s = &j->c[i];
        u64 o = output(y, s->position);
        if (s->mission) {
            if (s->has_lo) {
                u64 k = output((o + y) & 0xffffffffULL, 1);
                if (k < s->lo || k > s->hi) return 0;
            }
            if (s->tree && !tree_ok(s->tree, o)) return 0;
        } else if (o < s->lo || o > s->hi) return 0;
    }
    return 1;
}

static void campaign(Job *j, const Inverter *seed_inv, u64 y) {
    u64 xs[64];
    int n = invert(seed_inv, y, xs);
    for (int i = 0; i < n; i++) {
        if (j->n == j->cap) { j->cap = j->cap ? j->cap * 2 : 256; j->seeds = realloc(j->seeds, j->cap * sizeof(u64)); }
        j->seeds[j->n++] = (xs[i] - (u64)planet) & 0xffffffffULL;
    }
}

static void run_job(Job *j, long long limit) {
    const Inverter *seed_inv = inverter(j->seed_position), *m_inv = NULL;
    const Tree *root_tree = NULL;
    Walk w;
    if (j->root_kind == 0) walk_init(&w, 1, 0, 0xffffffffULL), w.all = 1;
    else walk_init(&w, j->root_position, j->root_lo, j->root_hi);
    if (j->root_kind == 2) {
        const Constraint *step = &j->c[j->root_step - 1];
        root_tree = step->tree; m_inv = inverter(step->position);
    }
    int phase = 1; i64 lim = 1LL << 32, s = (i64)j->s0; u64 off;
    int have = walk_start(&w, &s, &off);
    j->steps = 0; j->n = 0;
    u64 ys[64];
    while (j->steps < limit) {
        if (!have || s >= lim) {
            if (phase == 2 || j->s0 == 0) break;
            phase = 2; lim = (i64)j->s0; s = 0;
            have = walk_start(&w, &s, &off);
            continue;
        }
        u64 v = (u64)s;
        walk_advance(&w, &s, &off);
        j->steps++;
        if (j->root_kind != 2) { if (path_ok(j, v)) campaign(j, seed_inv, v); }
        else if (tree_ok(root_tree, v)) {
            int n = invert(m_inv, v, ys);
            for (int i = 0; i < n; i++) if (path_ok(j, ys[i])) campaign(j, seed_inv, ys[i]);
        }
    }
}

static int cmp(const void *a, const void *b) { u64 x = *(const u64 *)a, y = *(const u64 *)b; return x < y ? -1 : x > y; }

static Job *jobs; static int njobs; static long long limit; static int repeat = 1;
static volatile LONG next_job;
static DWORD WINAPI worker(LPVOID unused) {
    (void)unused;
    for (;;) {
        LONG k = InterlockedIncrement(&next_job) - 1;
        if (k >= njobs * repeat) return 0;
        Job local = jobs[k % njobs];
        local.seeds = NULL; local.cap = 0;
        run_job(&local, limit);
        free(local.seeds);
    }
}

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "solver_bench <jobs.txt> [threads] [repeat]\n"); return 2; }
    int threads = argc > 2 ? atoi(argv[2]) : 1;
    repeat = argc > 3 ? atoi(argv[3]) : 1;
    A[0] = 1; C[0] = 0;
    for (int p = 1; p <= MAXP; p++) { A[p] = A[p - 1] * 6364136223846793005ULL; C[p] = C[p - 1] * 6364136223846793005ULL + 1442695040888963407ULL; }
    for (int p = 1; p <= MAXP; p++) inverter(p);
    in = fopen(argv[1], "r");
    if (!in) { perror(argv[1]); return 1; }
    planet = (int)num(); njobs = (int)num(); limit = (long long)num();
    jobs = calloc(njobs, sizeof(Job));
    for (int k = 0; k < njobs; k++) {
        Job *j = &jobs[k];
        j->s0 = unum(); j->seed_position = (int)num(); j->root_kind = (int)num(); j->root_position = (int)num();
        j->root_lo = unum(); j->root_hi = unum(); j->root_step = (int)num();
        j->nc = (int)num(); j->c = calloc(j->nc, sizeof(Constraint));
        for (int i = 0; i < j->nc; i++) {
            Constraint *c = &j->c[i];
            c->mission = (int)num(); c->position = (int)num(); c->has_lo = (int)num(); c->lo = unum(); c->hi = unum();
            if ((int)num()) c->tree = read_tree();
        }
        j->lua_steps = (long long)num(); j->lua_n = (int)num();
        j->lua_seeds = calloc(j->lua_n + 1, sizeof(u64));
        for (int i = 0; i < j->lua_n; i++) j->lua_seeds[i] = unum();
        /* The trailing "# lua_seconds t" comment. */
        char tok[64]; fscanf(in, "%63s %63s %lf", tok, tok, &j->lua_seconds);
    }
    fclose(in);

    /* Single thread: per-job time and check against LuaJIT. */
    LARGE_INTEGER f, t0, t1; QueryPerformanceFrequency(&f);
    long long steps = 0; double lua = 0, c_time = 0; int mismatches = 0, cands = 0;
    for (int k = 0; k < njobs; k++) {
        Job *j = &jobs[k];
        QueryPerformanceCounter(&t0); run_job(j, limit); QueryPerformanceCounter(&t1);
        j->seconds = (double)(t1.QuadPart - t0.QuadPart) / f.QuadPart;
        steps += j->steps; c_time += j->seconds; lua += j->lua_seconds; cands += j->n;
        /* LuaJIT stops with candidates of the last step still pending, so
           its seeds must be a subset of C's and differ by at most a few. */
        qsort(j->seeds, j->n, sizeof(u64), cmp); qsort(j->lua_seeds, j->lua_n, sizeof(u64), cmp);
        int missing = 0;
        for (int i = 0; i < j->lua_n; i++) if (!bsearch(&j->lua_seeds[i], j->seeds, j->n, sizeof(u64), cmp)) missing++;
        if (j->steps != j->lua_steps || missing || j->n - j->lua_n > 8) {
            mismatches++;
            printf("job %d MISMATCH steps c=%lld lua=%lld seeds c=%d lua=%d missing=%d\n", k, j->steps, j->lua_steps, j->n, j->lua_n, missing);
        }
    }
    printf("1 thread: %lld steps in %.3f s = %.0f steps/s (LuaJIT %.3f s = %.0f steps/s, %.1fx); %d candidates; %d mismatching jobs\n",
           steps, c_time, steps / c_time, lua, steps / lua, lua / c_time, cands, mismatches);

    if (threads > 1) {
        HANDLE h[64];
        next_job = 0;
        QueryPerformanceCounter(&t0);
        for (int i = 0; i < threads; i++) h[i] = CreateThread(NULL, 0, worker, NULL, 0, NULL);
        WaitForMultipleObjects(threads, h, TRUE, INFINITE);
        QueryPerformanceCounter(&t1);
        double t = (double)(t1.QuadPart - t0.QuadPart) / f.QuadPart;
        printf("%d threads: %lld steps in %.3f s = %.0f steps/s (%.1fx LuaJIT)\n", threads, steps * repeat, t,
               steps * repeat / t, (steps * repeat / t) / (steps / lua));
    }
    return mismatches ? 1 : 0;
}
