// std: c++17
// std::string_view (GCC 7 and later).
#include <string_view>
int main() { std::string_view v = "abc"; return v.size() == 3 ? 0 : 1; }
