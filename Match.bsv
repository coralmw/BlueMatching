import FIFO::*;

// `define NUM_NODES 16
typedef UInt#(TLog#(16)) Idx;
typedef Bit#(16) Node; // we need 1 bit per node; as each node cound be reached by any other

interface MatchIfc;
  method Action reset();
  method Action start(Node syndrome);
  // get a match from the given syndrome. Each bit is set if that graph node is in the match path
  method ActionValue#(Node) get_match();
  method State getState();
endinterface

typedef enum { IDLE, SEARCH, REDUCE, FINISHED } State deriving (Eq, Bits);

(* descending_urgency = "reducematch_expand_high, reducematch_expand_low" *)
module mkMatch(MatchIfc);

  //lets assume a matching on a 4x4 grid for now, and we can consume a weight matrix
  // as a type param later.

  // the idea of a MWPM is to expand a match from each bit set in the syndrome
  // until you have a full path through the matrix.

  Reg#(State) state <- mkReg(IDLE);

  // each element of this is a MWPM as a bitfield with 1's for nodes that are involved in
  // each possible result.
  FIFO#(Node) resultFIFO <- mkFIFO();

  // this will contain the index of the node where a match was first found.
  // we grow the match chain back out from there to find the MWPM
  Reg#(Maybe#(Idx)) match_loc <- mkReg(Invalid); // tuple2(0,0)

  // each bit sets if that bit is part of a match chain from that bit.
  // a match has been found when we try to set a bit on a matrix location that
  // has a bit set.
  Reg#(Node) matchmatrix[16];
  for (Integer i=0; i<16; i=i+1)
      matchmatrix[i] <- mkReg(0);

  rule findmatch(state == SEARCH);
    $display("running search step");
    Maybe#(Idx) proposed_match = Invalid;
    // for (Integer i=0; i<16; i=i+1)
    //     proposed_match[i] = Invalid;

    for (Integer i_int=0; i_int<16; i_int=i_int+1) begin
      Idx i = fromInteger(i_int);

      Node updated_match = matchmatrix[i];

      // bloom. This is a fixed 2d square grid
      // for a arbitary grid we need to generate the fetches each step;
      // and may need to split into multiple cycles esp. if there are unequal radixes (nos of edges per node)
      // Idx l = (i+1) % 16;
      // Idx r = (i-1) % 16;
      // Idx u = (i+4) % 16;
      // Idx d = (i-4) % 16;

      updated_match = updated_match &
                      matchmatrix[i+1] &
                      matchmatrix[i-1] &
                      matchmatrix[i+4] &
                      matchmatrix[i-4];

      // detect a match chain; if more than 1 bit is set then this node
      // is part of a shortest path from 2 syndrome errors.
      Integer match_count = 0;
      for (Integer k=0; k<16; k=k+1)
        if (updated_match[k] == 1)
          match_count = 1 + match_count;

      if (updated_match > 1) begin
        proposed_match = Valid(i);
      end

      matchmatrix[i] <= updated_match;
    end

    if (proposed_match matches tagged Valid .idx) begin
      $display("found match", $time);
      match_loc <= proposed_match;
      state <= REDUCE;
    end

  endrule: findmatch


  // needs to match the target node ID
  Reg#(Maybe#(Idx)) match_high_target_node <- mkReg(Invalid); // node we are looking for
  Reg#(Maybe#(Idx)) match_high_current_front <- mkReg(Invalid); // node we are currently testing
  Reg#(Node) match_in_progress_high <- mkReg(0); // path so far (bits 1 if on path from midpoint to syndrome)

  Reg#(Maybe#(Idx)) match_low_target_node <- mkReg(Invalid); // node we are looking for
  Reg#(Maybe#(Idx)) match_low_current_front <- mkReg(Invalid); // node we are currently testing
  Reg#(Node) match_in_progress_low <- mkReg(0); // path so far (bits 1 if on path from midpoint to syndrome)


  rule reducematch_identify_sources(state == REDUCE && isValid(match_loc) );
    // match_loc contains a 2-tuple with the middle of a match.
    // we need to work backwards, adding the nodes involved in that chain to a match.
    Idx loc = fromMaybe(?, match_loc);
    Node mached_node = matchmatrix[loc];
    match_loc <= Invalid;

    match_in_progress_high <= 1<<pack(loc); // add the current node to the match.
    // Arbit. add to the higher syndrome node path
    match_in_progress_low <= 0;

    match_high_current_front <= Valid(loc);
    match_low_current_front <= Valid(loc); // both high and low search from here

    // count up to find the highest set bit
    Maybe#(Idx) high = Invalid;
    Maybe#(Idx) low = Invalid;

    for (Integer i=0; i<16; i=i+1) begin
      if (pack(mached_node)[i] == 1)
        high = Valid(1<<i);
    end
    match_high_target_node <= high; // lower set bit in the match_loc

    // and down
    for (Integer i=15; i>=0; i=i-1) begin
      if (pack(mached_node)[i] == 1)
        low = Valid(1<<i); // lower set bit in the match_loc
    end
    match_low_target_node <= low; // lower set bit in the match_loc

  endrule: reducematch_identify_sources

  rule reducematch_expand_high (state == REDUCE && isValid(match_high_current_front) && !isValid(match_loc) );
    // find node in neighborhood with tgt bit set
    // add target to path
    // if target != source, replace match_high_current_front with target
    Idx i = fromMaybe(?, match_high_current_front);
    Node onehot_i = (1<<i);

    Idx target = fromMaybe(?, match_high_target_node);
    matchmatrix[i] <= matchmatrix[i] | (1 << i);

    Node left = matchmatrix[i+1];
    Node right = matchmatrix[i-1];
    Node up = matchmatrix[i+4];
    Node down = matchmatrix[i-4];

    if ((left & onehot_i) == onehot_i) begin // ugh. This should test if the node to the left has the target bit set.
      match_in_progress_high <= match_in_progress_high & (1 << (i+1));
      if (i+1 != target) begin
        match_high_current_front <= Valid(i+4);
      end else begin
        match_high_current_front <= Invalid;
      end

    end else if ((right & onehot_i) == onehot_i) begin
      match_in_progress_high <= match_in_progress_high & (1 << (i-1));

      if (i-1 != target) begin
        match_high_current_front <= Valid(i-1);
      end else begin
        match_high_current_front <= Invalid;
      end

    end else if ((up & onehot_i) == onehot_i) begin
      match_in_progress_high <= match_in_progress_high & (1 << (i+4));

      if (i+4 != target) begin
        match_high_current_front <= Valid(i+4);
      end else begin
        match_high_current_front <= Invalid;
      end

    end else if ((down & onehot_i) == onehot_i) begin
      match_in_progress_high <= match_in_progress_high & (1 << (i-4));

      if (i-4 != target) begin
        match_high_current_front <= Valid(i-4);
      end else begin
        match_high_current_front <= Invalid;
      end

    end else begin
      match_high_current_front <= Invalid;
      $error("end of high path not at source, BUG!!");
    end

  endrule

  rule reducematch_expand_low (state == REDUCE && isValid(match_low_current_front) && !isValid(match_loc) );
    // find node in neighborhood with tgt bit set
    // add target to path
    // if target != source, replace match_low_current_front with target
    Idx i = fromMaybe(?, match_low_current_front);
    Node onehot_i = (1<<i);

    Idx target = fromMaybe(?, match_low_target_node);
    matchmatrix[i] <= matchmatrix[i] | (1 << i);

    Node left = matchmatrix[i+1];
    Node right = matchmatrix[i-1];
    Node up = matchmatrix[i+4];
    Node down = matchmatrix[i-4];

    if ((left & onehot_i) == onehot_i) begin // ugh. This should test if the node to the left has the target bit set.
      match_in_progress_low <= match_in_progress_low & (1 << (i+1));
      if (i+1 != target) begin
        match_low_current_front <= Valid(i+4);
      end else begin
        match_low_current_front <= Invalid;
      end

    end else if ((right & onehot_i) == onehot_i) begin
      match_in_progress_low <= match_in_progress_low & (1 << (i-1));

      if (i-1 != target) begin
        match_low_current_front <= Valid(i-1);
      end else begin
        match_low_current_front <= Invalid;
      end

    end else if ((up & onehot_i) == onehot_i) begin
      match_in_progress_low <= match_in_progress_low & (1 << (i+4));

      if (i+4 != target) begin
        match_low_current_front <= Valid(i+4);
      end else begin
        match_low_current_front <= Invalid;
      end

    end else if ((down & onehot_i) == onehot_i) begin
      match_in_progress_low <= match_in_progress_low & (1 << (i-4));

      if (i-4 != target) begin
        match_low_current_front <= Valid(i-4);
      end else begin
        match_low_current_front <= Invalid;
      end

    end else begin
      match_low_current_front <= Invalid;
      $error("end of low path not at source, BUG!!");
    end

  endrule

  rule reducematch_finish ( state == REDUCE &&
                            !isValid(match_high_current_front) &&
                            !isValid(match_low_current_front) &&
                            !isValid(match_loc) );
    state <= FINISHED;
    $display("found path ", match_in_progress_high & match_in_progress_low);

  endrule

  method Action reset();
    for (Integer i=0; i<16; i=i+1)
        matchmatrix[i] <= 0;
  endmethod

  method Action start(Node syndrome);
    $display("updating the node matrix", $time);
    for (Integer i=0; i<16; i=i+1)
      if (syndrome[i] == 1)
        matchmatrix[i*i] <= 1;
    state <= SEARCH;
  endmethod

  method State getState();
    return state;
  endmethod


  method ActionValue#(Node) get_match() if (state == FINISHED);
    state <= IDLE;
    $display("returning path ", match_in_progress_high & match_in_progress_low);
    return match_in_progress_high & match_in_progress_low;
  endmethod



endmodule
