

import types from require "tableshape"

describe "paypal", ->
  describe "adaptive payments", ->
    it "creates a paypal object", ->
      import AdaptivePayments from require "payments.paypal"


