/* Milestone 1 toolchain test: floating point under the chosen ABI.
 *
 * Usage: float
 *
 * Checks arithmetic, the maths library, printf formatting and strtod round
 * trips, then prints INFO lines with the in-memory layout of a double (which
 * differs between FPA and VFP conventions) and a rough timing figure that
 * helps compare the soft-float and VFP builds.
 * Exits 1 if any check failed, otherwise 0.
 */

#include <float.h>
#include <limits.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static int failures;

static void
check (int ok, const char *what, const char *detail)
{
  printf ("%s %s%s%s\n", ok ? "PASS" : "FAIL", what,
          detail && *detail ? ": " : "", detail ? detail : "");
  fflush (stdout);
  if (!ok)
    failures++;
}

static void
check_close (double got, double want, double tolerance, const char *what)
{
  char detail[96];
  snprintf (detail, sizeof detail, "got %.17g, want %.17g", got, want);
  check (fabs (got - want) <= tolerance, what, detail);
}

static int
same_bits (double a, double b)
{
  return memcmp (&a, &b, sizeof a) == 0;
}

int
main (void)
{
  /* volatile stops the compiler folding these at compile time, so the
     run-time floating-point code is what gets tested. */
  volatile double tenth = 0.1, fifth = 0.2, two = 2.0, one = 1.0;
  volatile double pi = 3.141592653589793, minus_two_half = -2.5;
  volatile float twof = 2.0f;
  volatile int imax = INT_MAX;
  static const double round_trip[] = {
    0.1, 1.0 / 3.0, 123456.789, 1e300, 2.2250738585072014e-308,
    4.9406564584124654e-324, -0.0, 6.02214076e23
  };
  char buf[64];
  unsigned i;
  clock_t start, stop;
  volatile double acc;
  const double one_d = 1.0;
  const unsigned char *bytes = (const unsigned char *) &one_d;

  printf ("float: TeX Live for RISC OS toolchain test\n");
#if defined(__SOFTFP__)
  printf ("INFO compiled for: soft-float (no FPU instructions)\n");
#elif defined(__VFP_FP__)
  printf ("INFO compiled for: VFP\n");
#else
  printf ("INFO compiled for: FPA or unknown\n");
#endif

  check_close (tenth + fifth, 0.3, 1e-15, "0.1 + 0.2 is close to 0.3");
  check (tenth + fifth != 0.3, "0.1 + 0.2 is not exactly 0.3 (IEEE double)", NULL);
  check_close (sqrt (two), 1.4142135623730951, 1e-15, "sqrt(2)");
  check_close (exp (one), 2.718281828459045, 1e-15, "exp(1)");
  check_close (log (two), 0.6931471805599453, 1e-15, "log(2)");
  check_close (sin (pi / 6.0), 0.5, 1e-15, "sin(pi/6)");
  check_close (pow (two, 0.5), 1.4142135623730951, 1e-15, "pow(2, 0.5)");
  check_close (floor (minus_two_half), -3.0, 0.0, "floor(-2.5)");
  check_close ((double) sqrtf (twof), 1.41421356, 1e-6, "sqrtf(2) in single precision");
  check ((int) (two + 1.99) == 3, "double to int conversion truncates", NULL);
  check ((double) imax == 2147483647.0, "int to double conversion", NULL);

  snprintf (buf, sizeof buf, "%.17g", tenth);
  check (strcmp (buf, "0.10000000000000001") == 0, "printf %.17g of 0.1", buf);
  snprintf (buf, sizeof buf, "%g", 1e-5);
  check (strcmp (buf, "1e-05") == 0, "printf %g of 1e-5", buf);
  snprintf (buf, sizeof buf, "%.3f", 2.0 / 3.0);
  check (strcmp (buf, "0.667") == 0, "printf %.3f of 2/3", buf);

  for (i = 0; i < sizeof round_trip / sizeof round_trip[0]; i++)
    {
      char what[96];
      double back;
      snprintf (buf, sizeof buf, "%.17g", round_trip[i]);
      back = strtod (buf, NULL);
      snprintf (what, sizeof what, "strtod round trip of %s", buf);
      check (same_bits (back, round_trip[i]), what, NULL);
    }

  check (DBL_MANT_DIG == 53, "DBL_MANT_DIG is 53", NULL);

  printf ("INFO bytes of 1.0 in memory:");
  for (i = 0; i < sizeof one_d; i++)
    printf (" %02x", bytes[i]);
  printf (" (00 00 00 00 00 00 f0 3f is little-endian IEEE; "
          "00 00 f0 3f 00 00 00 00 is FPA word order)\n");

  start = clock ();
  acc = 0.0;
  for (i = 0; i < 2000000u; i++)
    acc = acc * 0.999999 + 1.000001;
  stop = clock ();
  printf ("INFO 2,000,000 multiply-adds took %.2f s (result %.6g)\n",
          (double) (stop - start) / CLOCKS_PER_SEC, acc);

  printf ("float: %d check(s) failed\n", failures);
  return failures ? 1 : 0;
}
