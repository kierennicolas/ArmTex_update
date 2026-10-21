// std: c++11
// thread_local storage (GCC 4.8 and later; also needs TLS support in the target).
thread_local int counter = 0;
int main() { return counter; }
