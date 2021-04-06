import Match::*;
import StmtFSM::*;

(* synthesize *)
module mkTestMatch(Empty);

  let dut <- mkMatch();
  Reg#(Node) matched <- mkReg(0);

  Stmt test =
  seq
    dut.reset();
    dut.start(5); // locations 1 and 4 are hot, so the path should be 1 2 4

    await(dut.getState() == FINISHED);
    action
      $display("dut found a match");
      ActionValue#(Match::Node) _matched = dut.get_match();
    endaction

    $finish();
  endseq;

  FSM testFSM <- mkFSM (test);

  rule startit;
    testFSM.start();
  endrule

  // rule alwaysrun;
  //   $display("dut in state: ", dut.getState(), $time);
  // endrule
endmodule
