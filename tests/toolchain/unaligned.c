/* Milestone 1 toolchain test: unaligned memory access.
 *
 * Usage: unaligned
 *
 * Compilers targeting ARMv6 and later may emit single load instructions for
 * data that is not naturally aligned. Whether that works depends on how the
 * operating system configures alignment checking, so we need to measure it on
 * RISC OS 5.30 on Titanium. The tests go from safe to risky. A fault is caught
 * with a signal handler where UnixLib delivers one, so the program can report
 * it and carry on; the "about to" lines show how far it got if it cannot.
 *
 * Exits 1 if any check failed, otherwise 0.
 */

#include <setjmp.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static int failures;
static sigjmp_buf recover;
static volatile sig_atomic_t fault_signal;

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
on_fault (int sig)
{
  fault_signal = sig;
  siglongjmp (recover, 1);
}

struct __attribute__ ((packed)) record
{
  uint8_t tag;
  uint32_t word;
  uint16_t half;
  uint64_t dword;
};

/* Little-endian value of n bytes starting at p. */
static uint64_t
expected_le (const unsigned char *p, int n)
{
  uint64_t v = 0;
  int i;
  for (i = n - 1; i >= 0; i--)
    v = (v << 8) | p[i];
  return v;
}

/* Runs one risky step. Returns 1 if it completed, 0 if it faulted. */
#define GUARDED(label, statement)                                         \
  do                                                                      \
    {                                                                     \
      printf ("about to: %s\n", label);                                   \
      fflush (stdout);                                                    \
      fault_signal = 0;                                                   \
      if (sigsetjmp (recover, 1) == 0)                                    \
        {                                                                 \
          statement;                                                      \
        }                                                                 \
      else                                                                \
        {                                                                 \
          char detail[48];                                                \
          snprintf (detail, sizeof detail, "faulted with signal %d",      \
                    (int) fault_signal);                                  \
          check (0, label, detail);                                       \
        }                                                                 \
    }                                                                     \
  while (0)

/* Like GUARDED, but for behaviour with no fixed expectation: reports an INFO
   line instead of counting a failure. */
#define PROBED(label, statement)                                          \
  do                                                                      \
    {                                                                     \
      printf ("about to: %s\n", label);                                   \
      fflush (stdout);                                                    \
      fault_signal = 0;                                                   \
      if (sigsetjmp (recover, 1) == 0)                                    \
        {                                                                 \
          statement;                                                      \
        }                                                                 \
      else                                                                \
        {                                                                 \
          printf ("INFO %s: faulted with signal %d\n", label,             \
                  (int) fault_signal);                                    \
          fflush (stdout);                                                \
        }                                                                 \
    }                                                                     \
  while (0)

int
main (void)
{
  unsigned char buf[40] __attribute__ ((aligned (8)));
  unsigned char *volatile base = buf;
  struct record *rec;
  uint32_t w;
  uint16_t h;
  uint64_t d;
  unsigned i;
  struct sigaction sa;

  printf ("unaligned: TeX Live for RISC OS toolchain test\n");
#if defined(__ARM_FEATURE_UNALIGNED)
  printf ("INFO compiler may emit unaligned loads (__ARM_FEATURE_UNALIGNED defined)\n");
#else
  printf ("INFO compiler avoids unaligned loads (__ARM_FEATURE_UNALIGNED not defined)\n");
#endif

  memset (&sa, 0, sizeof sa);
  sa.sa_handler = on_fault;
  sigemptyset (&sa.sa_mask);
  sigaction (SIGSEGV, &sa, NULL);
  sigaction (SIGBUS, &sa, NULL);
  sigaction (SIGILL, &sa, NULL);

  for (i = 0; i < sizeof buf; i++)
    buf[i] = (unsigned char) (0x11 + i);

  /* 1. memcpy from an unaligned address: always safe. */
  memcpy (&w, base + 1, sizeof w);
  check (w == (uint32_t) expected_le (buf + 1, 4), "memcpy 32-bit from offset 1", NULL);

  /* 2. Members of a packed structure: the compiler chooses the loads. */
  rec = (struct record *) (base + 0);
  GUARDED ("packed 32-bit member at offset 1",
           check (rec->word == (uint32_t) expected_le (buf + 1, 4),
                  "packed 32-bit member at offset 1", NULL));
  GUARDED ("packed 16-bit member at offset 5",
           check (rec->half == (uint16_t) expected_le (buf + 5, 2),
                  "packed 16-bit member at offset 5", NULL));
  GUARDED ("packed 64-bit member at offset 7",
           check (rec->dword == expected_le (buf + 7, 8),
                  "packed 64-bit member at offset 7", NULL));

  /* 3. Plain loads through misaligned pointers. Undefined behaviour in C, but
     common in real code. A single LDR or LDRH works on ARMv7 only when
     alignment checking is off. */
  GUARDED ("32-bit load through a pointer at offset 1",
           w = *(volatile uint32_t *) (base + 1);
           check (w == (uint32_t) expected_le (buf + 1, 4),
                  "32-bit load through a pointer at offset 1", NULL));
  GUARDED ("16-bit load through a pointer at offset 3",
           h = *(volatile uint16_t *) (base + 3);
           check (h == (uint16_t) expected_le (buf + 3, 2),
                  "16-bit load through a pointer at offset 3", NULL));
  GUARDED ("32-bit store through a pointer at offset 9",
           *(volatile uint32_t *) (base + 9) = 0xa1b2c3d4u;
           check (expected_le (buf + 9, 4) == 0xa1b2c3d4u,
                  "32-bit store through a pointer at offset 9", NULL));

  /* 4. 64-bit loads through a pointer that is not even 4-byte aligned. ARMv7
     faults on a misaligned LDRD or LDM whatever the alignment setting, but the
     compiler may use other instructions, so this is reported, not judged. */
  PROBED ("64-bit load through a pointer at offset 2",
          d = *(volatile uint64_t *) (base + 2);
          printf ("INFO 64-bit load through a pointer at offset 2: %s\n",
                  d == expected_le (buf + 2, 8) ? "correct value" : "wrong value");
          fflush (stdout));

  printf ("unaligned: %d check(s) failed\n", failures);
  return failures ? 1 : 0;
}
