#include <bits/stdc++.h>

using namespace std;

constexpr long MOD = 0x10FF80;

class Polynomial {
private:
  vector<long> exp;
public:
  Polynomial(vector<long> const& v) : exp(v) {};
  long calculate(long x) {
    long ret = 0;
    for (auto it = exp.rbegin(); it != exp.rend(); ++it) {
      cout << ret << "\n";
      ret *= x;
      cout << "po domnozeniu: " << ret << "\n";
      ret %= MOD;
      cout << "po modulo: " << ret << "\n";
      ret += *it;
      cout << "po dodaniu: " << ret << "\n";
      ret %= MOD;
      cout << "po modulo: " << ret << "\n";
    }
    cout << ret << "\n";
    return ret;
  }
};

int main() {
  cout << "Give coeff count:\n";
  int n;
  cin >> n;
  cout << "Give coeffs as a0 .. an\n";
  vector<long> v(n);
  for (int i = 0; i < n; ++i)
    cin >> v[i];
  Polynomial p(v);
  long x = 0x5B759L;
  cout << p.calculate(x - 0x80) + 0x80;
  cout << "\n";
}
