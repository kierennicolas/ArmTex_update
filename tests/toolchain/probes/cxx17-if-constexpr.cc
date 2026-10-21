// std: c++17
// if constexpr (GCC 7 and later).
template <int N> int pick() { if constexpr (N > 0) return 1; else return 0; }
int main() { return pick<1>() == 1 ? 0 : 1; }
