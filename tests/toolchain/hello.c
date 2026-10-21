/* Milestone 1 toolchain test: basic C runtime behaviour under UnixLib.
 *
 * Usage: hello [--exit N]
 *
 * Prints one PASS or FAIL line per check, plus INFO lines that record
 * behaviour we need to know about but have no fixed expectation for.
 * Exits 1 if any check failed, otherwise 0. With --exit N it exits with
 * status N after the checks, so the test kit can confirm that the status
 * reaches Sys$ReturnCode.
 *
 * The test kit's Obey file sets TLTest$Var to "expected" and TLTEST_PLAIN to
 * "expected-plain" before running this, and runs it with the kit directory
 * as the current directory.
 */

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#ifdef __riscos__
#include <unixlib/local.h>
#endif

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
info (const char *what, const char *detail)
{
  printf ("INFO %s: %s\n", what, detail ? detail : "(null)");
  fflush (stdout);
}

static void
test_environment (void)
{
  const char *v = getenv ("TLTest$Var");
  check (v != NULL && strcmp (v, "expected") == 0,
         "getenv of RISC OS variable TLTest$Var", v ? v : "(unset)");

  /* Names without '$' come from UnixLib's private environment, not straight
     from the RISC OS variable. kpathsea reads TEXMFCNF and friends this way,
     so we need to know whether a variable set by an Obey file is visible. */
  v = getenv ("TLTEST_PLAIN");
  info ("getenv of TLTEST_PLAIN (no $, set by the Obey file)", v ? v : "(unset)");

  check (setenv ("TLTEST_SET", "round-trip", 1) == 0, "setenv", NULL);
  v = getenv ("TLTEST_SET");
  check (v != NULL && strcmp (v, "round-trip") == 0, "getenv after setenv",
         v ? v : "(unset)");
}

static void
test_files (void)
{
  const char *dir = "scratch";
  const char *path = "scratch/hello.txt";
  const char *renamed = "scratch/renamed.txt";
  const char *text = "line one\nline two\n";
  char buf[64];
  struct stat st;
  FILE *f;
  size_t n;

  if (mkdir (dir, 0777) != 0 && errno != EEXIST)
    check (0, "mkdir scratch", strerror (errno));
  else
    check (1, "mkdir scratch", NULL);

  f = fopen (path, "w");
  check (f != NULL, "fopen for writing with a Unix-style path", path);
  if (f == NULL)
    return;
  check (fputs (text, f) >= 0, "fputs", NULL);
  check (fclose (f) == 0, "fclose after writing", NULL);

  check (stat (path, &st) == 0 && st.st_size == (off_t) strlen (text),
         "stat reports the written size", NULL);

  f = fopen (path, "r");
  check (f != NULL, "fopen for reading", path);
  if (f == NULL)
    return;
  n = fread (buf, 1, sizeof buf - 1, f);
  buf[n] = '\0';
  check (strcmp (buf, text) == 0, "read back what was written", NULL);
  check (fseek (f, 5, SEEK_SET) == 0 && ftell (f) == 5, "fseek and ftell", NULL);
  fclose (f);

  check (rename (path, renamed) == 0, "rename", NULL);
  check (remove (renamed) == 0, "remove", NULL);
  check (stat (renamed, &st) != 0, "file gone after remove", NULL);

  f = tmpfile ();
  check (f != NULL, "tmpfile", f ? NULL : strerror (errno));
  if (f != NULL)
    {
      fputs ("temporary", f);
      rewind (f);
      n = fread (buf, 1, sizeof buf - 1, f);
      buf[n] = '\0';
      check (strcmp (buf, "temporary") == 0, "tmpfile read back", NULL);
      fclose (f);
    }
}

#ifdef __riscos__
/* Show how UnixLib turns Unix-style names into RISC OS names, with the default
   settings and with suffix swapping turned off. Milestone 2 uses this to
   settle the filename layout for the texmf tree. */
static void
test_name_translation (void)
{
  static const char *const names[] = {
    "article.cls",
    "texmf-dist/tex/latex/base/article.cls",
    "texmf-dist/fonts/tfm/public/cm/cmr10.tfm",
    "texmf-dist/fonts/enc/dvips/lm/lm-ec.enc",
    "texmf-dist/web2c/texmf.cnf",
    "foo.c",
    "dir.with.dots/file.name.tex",
    "../up.tex",
    "/tmp/x.log",
    NULL
  };
  static const struct { int flags; const char *label; } modes[] = {
    { 0, "default" },
    { __RISCOSIFY_NO_SUFFIX, "no suffix swapping" },
  };
  char buf[512];
  char line[700];
  unsigned m;
  int i;

  for (m = 0; m < sizeof modes / sizeof modes[0]; m++)
    for (i = 0; names[i] != NULL; i++)
      {
        int filetype = __RISCOSIFY_FILETYPE_NOTFOUND;
        const char *r = __riscosify (names[i], 0, modes[m].flags, buf,
                                     sizeof buf, &filetype);
        snprintf (line, sizeof line, "%s -> %s", names[i], r ? buf : "(failed)");
        printf ("INFO name translation (%s): %s\n", modes[m].label, line);
      }
  fflush (stdout);
}
#endif

int
main (int argc, char **argv)
{
  int exit_code = -1;
  char detail[64];
  time_t now;

  if (argc == 3 && strcmp (argv[1], "--exit") == 0)
    exit_code = atoi (argv[2]);

  printf ("hello: TeX Live for RISC OS toolchain test\n");
  check (argc >= 1 && argv[0] != NULL, "argv[0] present", argv[0]);

  test_environment ();
  test_files ();
#ifdef __riscos__
  test_name_translation ();
#endif

  now = time (NULL);
  snprintf (detail, sizeof detail, "%ld", (long) now);
  info ("time()", detail);
  if (now != (time_t) -1)
    {
      struct tm *tm = gmtime (&now);
      if (tm != NULL)
        {
          strftime (detail, sizeof detail, "%Y-%m-%d %H:%M:%S UTC", tm);
          info ("gmtime", detail);
        }
    }

  printf ("hello: %d check(s) failed\n", failures);
  if (exit_code >= 0)
    {
      printf ("hello: exiting with requested status %d\n", exit_code);
      return exit_code;
    }
  return failures ? 1 : 0;
}
