// std: c++11
// Standard attribute syntax (GCC 4.8 and later).
[[noreturn]] void stop();
void stop() { for (;;) {} }
int main() { return 0; }
