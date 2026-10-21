// std: c++11
// alignas and alignof (GCC 4.8 and later).
struct alignas(16) Aligned { char c; };
static_assert(alignof(Aligned) == 16, "alignas(16) honoured");
int main() { return 0; }
