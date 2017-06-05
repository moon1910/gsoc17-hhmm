functions {
  vector normalize(vector x) {
    return x / sum(x);
  }
}

data {
  int<lower=1> T;                   // number of observations (length)
  int<lower=1> K;                   // number of hidden states
  int<lower=1> M;                   // size of the input vector

  real x_t[T];                      // output (scalar so far)
  vector[M] u_tm[T];                 // input vectors
}

parameters {
  // Discrete state model
  simplex[K] p_1k;                  // initial state probabilities
  vector[M] w_km[K];                // state regressors

  // Continuous observation model
  vector[M] b_km[K];                // mean regressors
  real<lower=0.0001> s_k[K];        // residual standard deviations
}

transformed parameters {
  vector[K] unalpha_tk[T];
  // vector[K] unbeta_tk[T];
  // vector[K] ungamma_tk[T];

  vector[K] alpha_tk[T];
  // vector[K] beta_tk[T];
  // vector[K] gamma_tk[T];

  vector[K] unA_ij[T];
  vector[K] A_ij[T];

  { // Transition probability matrix p(z_t = j | z_{t-1} = i, u_tm)
    unA_ij[1] = p_1k; // Filler
    A_ij[1] = p_1k; // Filler
    for (t in 2:T) {
      for (j in 1:K) { // j = current (t)
        unA_ij[t][j] = u_tm[t]' * w_km[j];
      }
      A_ij[t] = softmax(unA_ij[t]);
    }
  }

  { // Forward algorithm log p(z_t = j | x_{1:t})
    real accumulator[K];

    for(j in 1:K)
      unalpha_tk[1][j] = log(p_1k[j]) + normal_lpdf(x_t[1] | u_tm[1]'* b_km[j], s_k[j]);

    for (t in 2:T) {
      for (j in 1:K) { // j = current (t)
        for (i in 1:K) { // i = previous (t-1)
                         // Murphy (2012) Eq. 17.48
                         // belief state + transition prob + local evidence at t
          accumulator[i] = unalpha_tk[t-1, i] + log(A_ij[t][i]) + normal_lpdf(x_t[t] | u_tm[t]'* b_km[j], s_k[j]);
        }
        unalpha_tk[t, j] = log_sum_exp(accumulator);
      }
    }

    for (t in 1:T)
      alpha_tk[t] = softmax(unalpha_tk[t]);
  } // Forward

  // { // Backward algorithm log p(x_{t+1:T} | z_t = j)
  //   real accumulator[K];
  //
  //   for (j in 1:K)
  //     unbeta_tk[T, j] = 1;
  //
  //   for (tforward in 0:(T-2)) {
  //     int t;
  //     t = T - tforward;
  //
  //     for (j in 1:K) { // j = previous (t-1)
  //       for (i in 1:K) { // i = next (t)
  //                        // Murphy (2012) Eq. 17.58
  //                        // backwards t  + transition prob + local evidence at t
  //         accumulator[i] = unbeta_tk[t, i] + log(A_ij[t][i]) + normal_lpdf(x_t[t] | u_tm[t]'* b_km[j], s_k[j]);
  //         }
  //       unbeta_tk[t-1, j] = log_sum_exp(accumulator);
  //     }
  //   }
  //
  //   for (t in 1:T)
  //     beta_tk[t] = softmax(unbeta_tk[t]);
  // } // Backward
  //
  // { // Forwards-backwards algorithm log p(z_t = j | x_{1:T})
  //   for(t in 1:T) {
  //       ungamma_tk[t] = alpha_tk[t] .* beta_tk[t];
  //   }
  //
  //   for(t in 1:T)
  //     gamma_tk[t] = normalize(ungamma_tk[t]);
  // } // Forwards-backwards
}

model {
  for(j in 1:K) {
    w_km[j] ~ normal(0, 5);
    b_km[j] ~ normal(0, 5);
    s_k[j] ~ normal(0, 3);
  }

  target += log_sum_exp(unalpha_tk[T]); // Note: update based only on last unalpha_tk
}

generated quantities {
  vector[K] hatpi_tk[T];
  int<lower=1, upper=K> hatz_t[T];
  real hatx_t[T];

  { // Fitted state
    vector[K] reg_tk[T];
    for(t in 1:T) {
      for(j in 1:K) {
        reg_tk[t, j] = u_tm[t]' * to_vector(w_km[j]);
      }
      hatpi_tk[t] = softmax(reg_tk[t]);
      hatz_t[t] = categorical_rng(hatpi_tk[t]);
    }
  }

  { // Fitted output
    real reg_tk[T];
    for(t in 1:T) {
      reg_tk[t] = u_tm[t]' * b_km[hatz_t[t]];
      hatx_t[t] = normal_rng(reg_tk[t], s_k[hatz_t[t]]);
    }
  }

  // int<lower=1, upper=K> zstar_t[T];
  // real logp_zstar;
  //
  // {
  //   int back_ptr[T, K];             // backpointer to the source of the link
  //   real best_total_logp;           // best probability for the whole chain
  //   real best_logp[T, K];           // max prob for the seq up to t
  //                                   // with final output from state k for time t
  //
  //   for (j in 1:K)
  //     best_logp[1, K] = normal_lpdf(x_t[1] | u_tm[1]'* b_km[j], s_k[j]);
  //
  //   for (t in 2:T) {
  //     for (j in 1:K) {
  //       best_logp[t, j] = negative_infinity();
  //       for (i in 1:K) {
  //         real logp;
  //         logp = best_logp[t-1, i] + log(A_ij[t][i]) + normal_lpdf(x_t[t] | u_tm[t]'* b_km[j], s_k[j]);
  //         if (logp > best_logp[t, j]) {
  //           back_ptr[t, j] = i;
  //           best_logp[t, j] = logp;
  //         }
  //       }
  //     }
  //   }
  //
  //   logp_zstar = max(best_logp[T]);
  //
  //   for (j in 1:K)
  //     if (best_logp[T, j] == logp_zstar)
  //       zstar_t[T] = j;
  //
  //   for (t in 1:(T - 1)) {
  //     zstar_t[T - t] = back_ptr[T - t + 1, zstar_t[T - t + 1]];
  //   }
  //
  // }
}
