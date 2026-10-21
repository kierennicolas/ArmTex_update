// std: c++11
// Inheriting constructors (GCC 4.8 and later).
struct Base { explicit Base(int v) : value(v) {} int value; };
struct Derived : Base { using Base::Base; };
int main() { Derived d(3); return d.value == 3 ? 0 : 1; }
