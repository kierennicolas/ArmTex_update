// std: c++11
// Ref-qualified member functions (GCC 4.8.1 and later).
struct S { int get() & { return 1; } int get() && { return 2; } };
int main() { S s; return s.get() == 1 && S().get() == 2 ? 0 : 1; }
