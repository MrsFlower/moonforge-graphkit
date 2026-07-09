///|
pub struct AuctionResult {
  quantity : Int
  price : Int
} derive(Eq)

///|
pub fn clearing_quantity(
  bids : FixedArray[Int],
  asks : FixedArray[Int],
) -> Int where {
  proof_require: same_length(bids, asks),
  proof_require: bids_desc(bids),
  proof_require: asks_asc(asks),
  proof_ensure: result => clearing_quantity_post(bids, asks, result),
} {
  for lo = 0, hi = bids.length(); lo < hi; {
    let mid = lo + (hi - lo) / 2
    if asks[mid] <= bids[mid] {
      continue mid + 1, hi
    } else {
      continue lo, mid
    }
  } nobreak {
    lo
  } where {
    // @MOONFORGE_INVARIANT_START
    // @MOONFORGE_INVARIANT_END
  }
}

///|
pub fn clear_book(
  bids : FixedArray[Int],
  asks : FixedArray[Int],
) -> AuctionResult where {
  proof_require: same_length(bids, asks),
  proof_require: bids_desc(bids),
  proof_require: asks_asc(asks),
  proof_ensure: result => auction_result_post(bids, asks, result),
} {
  let quantity = clearing_quantity(bids, asks)
  let price = if quantity == 0 {
    0
  } else {
    asks[quantity - 1] + (bids[quantity - 1] - asks[quantity - 1]) / 2
  }
  let result = { quantity, price }
  proof_assert auction_result_post(bids, asks, result)
  result
}
