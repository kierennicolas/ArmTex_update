// std: c++17
// std::optional (GCC 7 and later).
#include <optional>
int main() { std::optional<int> o = 3; return o.value_or(0) == 3 ? 0 : 1; }
