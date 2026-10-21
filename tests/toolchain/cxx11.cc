// Milestone 1 toolchain test: core C++11 language and library features.
//
// Usage: cxx11
//
// Covers the features the C++ parts of TeX Live (xpdf for pdfTeX, HarfBuzz
// for LuaHBTeX) rely on most: lambdas, smart pointers, move semantics,
// exceptions, static initialisation and the standard containers. Features
// that GCC 4.7 may lack are compile-only probes in probes/ instead, so this
// program tests what is expected to work.
// Compiled with -std=c++11. Exits 1 if any check failed, otherwise 0.

#include <algorithm>
#include <cstdio>
#include <functional>
#include <iostream>
#include <map>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace {

int failures = 0;

void check(bool ok, const char *what) {
  std::printf("%s %s\n", ok ? "PASS" : "FAIL", what);
  std::fflush(stdout);
  if (!ok)
    ++failures;
}

struct Counter {
  static int constructed;
  Counter() { ++constructed; }
};
int Counter::constructed = 0;
Counter global_counter;  // must be constructed before main runs

template <typename... Ts>
int count_args(Ts...) {
  return sizeof...(Ts);
}

constexpr int square(int x) { return x * x; }

struct MoveOnly {
  std::unique_ptr<int> value;
  explicit MoveOnly(int v) : value(new int(v)) {}
};

enum class Colour { red, green };

struct Base {
  virtual ~Base() {}
  virtual int id() const { return 1; }
};
struct Derived : Base {
  int id() const override { return 2; }
};

}  // namespace

int main() {
  std::cout << "cxx11: TeX Live for RISC OS toolchain test" << std::endl;

  check(Counter::constructed == 1, "static initialisation before main");

  auto answer = 42;
  check(answer == 42, "auto");

  int captured = 5;
  auto add = [captured](int y) { return captured + y; };
  check(add(3) == 8, "lambda with capture");

  std::function<int(int)> wrapped = add;
  check(wrapped(1) == 6, "std::function");

  std::vector<int> v = {3, 1, 2};
  int sum = 0;
  for (int i : v)
    sum += i;
  check(sum == 6, "initializer list and range-based for");

  std::sort(v.begin(), v.end(), [](int a, int b) { return a > b; });
  check(v[0] == 3 && v[2] == 1, "std::sort with a lambda comparator");

  std::unique_ptr<int> up(new int(7));
  std::unique_ptr<int> up2 = std::move(up);
  check(!up && *up2 == 7, "std::unique_ptr and std::move");

  std::shared_ptr<int> sp = std::make_shared<int>(9);
  std::shared_ptr<int> sp2 = sp;
  check(sp.use_count() == 2 && *sp2 == 9, "std::shared_ptr");

  std::map<std::string, int> m;
  m["alpha"] = 1;
  m["beta"] = 2;
  check(m.size() == 2 && m["beta"] == 2, "std::map with std::string keys");

  bool caught = false;
  try {
    throw std::runtime_error("boom");
  } catch (const std::exception &e) {
    caught = std::string(e.what()) == "boom";
  }
  check(caught, "exception thrown and caught");

  bool caught_nested = false;
  try {
    try {
      throw 7;
    } catch (int) {
      throw std::logic_error("rethrown");
    }
  } catch (const std::logic_error &) {
    caught_nested = true;
  }
  check(caught_nested, "exception thrown from a catch block");

  check(count_args(1, 'a', 2.0) == 3, "variadic templates");

  static_assert(square(4) == 16, "constexpr evaluated at compile time");
  check(true, "constexpr and static_assert");

  int *null_pointer = nullptr;
  check(null_pointer == 0, "nullptr");

  Colour c = Colour::green;
  check(c != Colour::red, "enum class");

  std::vector<MoveOnly> movable;
  movable.push_back(MoveOnly(3));
  movable.emplace_back(4);
  check(movable.size() == 2 && *movable[1].value == 4,
        "move-only type in std::vector");

  std::unique_ptr<Base> poly(new Derived);
  check(poly->id() == 2 && dynamic_cast<Derived *>(poly.get()) != nullptr,
        "virtual dispatch and dynamic_cast");

  std::ostringstream out;
  out << "value=" << 12 << ' ' << 1.5;
  check(out.str() == "value=12 1.5", "std::ostringstream formatting");

  std::cout << "cxx11: " << failures << " check(s) failed" << std::endl;
  return failures ? 1 : 0;
}
