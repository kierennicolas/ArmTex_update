// std: c++11
// std::mutex (used by ICU; needs thread support in the C++ library).
#include <mutex>
std::mutex lock;
int main() { std::lock_guard<std::mutex> guard(lock); return 0; }
