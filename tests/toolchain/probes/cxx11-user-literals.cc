// std: c++11
// User-defined literals (GCC 4.7 and later).
constexpr unsigned long long operator"" _kib(unsigned long long v) { return v * 1024; }
static_assert(2_kib == 2048, "user-defined literal");
int main() { return 0; }
