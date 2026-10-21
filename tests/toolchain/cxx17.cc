// Milestone 1 toolchain probe: C++17 features of the kind ICU 75 and later
// require.
//
// Usage: cxx17
//
// This is a probe: GCC 4.7 predates C++17, so it is expected not to compile
// there. The build records the result either way. If it does compile, the kit
// runs it, and it exits 1 if any check failed, otherwise 0.

#include <cstdio>
#include <map>
#include <optional>
#include <string>
#include <string_view>
#include <tuple>

namespace {

int failures = 0;

void check(bool ok, const char *what) {
  std::printf("%s %s\n", ok ? "PASS" : "FAIL", what);
  std::fflush(stdout);
  if (!ok)
    ++failures;
}

inline constexpr int kAnswer = 42;  // inline variable

template <typename T>
int kind_of(T) {
  if constexpr (sizeof(T) == 1)
    return 1;
  else
    return 2;
}

std::optional<int> parse_digit(std::string_view s) {
  if (s.size() == 1 && s[0] >= '0' && s[0] <= '9')
    return s[0] - '0';
  return std::nullopt;
}

}  // namespace

int main() {
  std::printf("cxx17: TeX Live for RISC OS toolchain probe\n");

  check(kAnswer == 42, "inline variable");
  check(kind_of('x') == 1 && kind_of(1.0) == 2, "if constexpr");

  auto seven = parse_digit("7");
  check(seven.has_value() && *seven == 7, "std::optional with a value");
  check(!parse_digit("x").has_value(), "std::optional without a value");

  std::string_view view = "hello world";
  check(view.substr(6) == "world", "std::string_view");

  std::map<std::string, int> m{{"a", 1}, {"b", 2}};
  int total = 0;
  for (const auto &[key, value] : m)
    total += value + static_cast<int>(key.size());
  check(total == 5, "structured bindings");

  auto [x, y] = std::make_tuple(1, 2.5);
  check(x == 1 && y == 2.5, "structured bindings from a tuple");

  std::printf("cxx17: %d check(s) failed\n", failures);
  return failures ? 1 : 0;
}
