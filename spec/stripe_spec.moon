import types from require "tableshape"
import extract_params, make_http, assert_shape from require "spec.helpers"

describe "stripe", ->
  it "creates a stripe object", ->
    import Stripe from require "payments.stripe"
    stripe = assert Stripe "client_id", "client_secret", "publishable_key"
