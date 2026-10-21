// std: c++14
// Generic lambdas (GCC 4.9 and later).
int main() { auto twice = [](auto v) { return v + v; }; return twice(2) == 4 ? 0 : 1; }
