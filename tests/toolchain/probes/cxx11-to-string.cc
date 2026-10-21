// std: c++11
// std::to_string (needs C99 support in libstdc++).
#include <string>
int main() { return std::to_string(123) == "123" ? 0 : 1; }
