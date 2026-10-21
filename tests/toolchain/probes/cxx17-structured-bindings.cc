// std: c++17
// Structured bindings (GCC 7 and later).
#include <utility>
int main() { auto [a, b] = std::make_pair(1, 2); return a + b == 3 ? 0 : 1; }
