// std: c++14
// std::make_unique (GCC 4.9 and later).
#include <memory>
int main() { auto p = std::make_unique<int>(5); return *p == 5 ? 0 : 1; }
