// std: c++11
// std::atomic (used by HarfBuzz and ICU).
#include <atomic>
std::atomic<int> refcount(1);
int main() { refcount.fetch_add(1); return refcount.load() == 2 ? 0 : 1; }
