pragma solidity ^0.4.16;
import './api.sol';
import './strings.sol';

/**
 * @title Ownable
 * @dev The Ownable contract has an owner address, and provides basic authorization control
 * function, this simplifies the implementation of "user permissions".
 */
contract Ownable {
  address public owner;
  
  event OwnershipTransferred(
    address indexed previousOwner,
    address indexed newOwner
  );

  /**
   * @dev The Ownable constructor sets the original `owner` of the contract to the sender account. 
   */
  constructor() public {
    owner = msg.sender;
  }

  /** 
   * @dev Throws if called by any account other than the owner.
   */
  modifier onlyOwner() {
    require(msg.sender == owner);
    _;
  }

  /** 
   * @dev Allow the current owner to transfer control of the contract to a newOwner.
   * @param newOwner The address to transfer ownership to.
   */
  function transferOwnership(address newOwner) public onlyOwner() {
    require(newOwner != address(0));
    emit OwnershipTransferred(owner, newOwner);
    owner = newOwner;
  }
}

/**
 * @title TEST_NAME
 * @dev The TEST_NAME contract has functionality for admin to add multiple questions and answer and other options like intitial_start_date, no_of_days_submit, no_of_days_commit, no_of_days_before_result, no_of_days_result_active in contract. user can vote for questions and win ether.
 */
contract TEST_NAME is Ownable {
  using strings for *;
  DateTimeAPI private dateTimeUtils;
  
  event logTransfer(address from, address to, uint amount);
  event logQuestionInfo(string info, uint q_id);
  event logQuestionCycle(string info, uint q_id);
  event logQuestionCycleCommit(string info, uint[] q_id);
  event logBoolEvent(string info, bool _condition);

  uint public TOTAL_NofQUESTIONS = 1; // total count of questions updated each time admin updates questions db.
  uint public CYCLE_ID = 1; // total count of questions cycle each time result is calculated.
  
  enum Status { submitted, committed, failedcommit, resultdeclared } // submitted, committed, failedcommit, resultdeclared
  
  mapping (address => uint) public userBalance;
  
  struct Question {
    string QuestionText; // question
    string Answers; // "lorem ipsum, lorem ipsum"
    uint AnswerCount; // number of options avaliable
    uint NofAnswersLimit; // number of user can attemp question
    uint IntitialStartDate; // First time start date 1528191889
    uint NofDays_Submit; // 6 i.e.x sec
    uint NofDays_Commit; // 2
    uint NofDays_BeforeResult; // 1
    uint NofDays_RepeatAfterResult; // 20
    uint RepeatCount; // number of time question repeat
    uint Cost; // cost of question in kwei
    uint repeatFlag;
  }
  
  // QUESTIONS: array of Question, where QID is assumed to be an integer....0,1,2....
  // Each Question is added to "QUESTIONS" from the Admin be calling a writeable SC method addQuestions(QueStr as string)
  mapping (uint => Question) public QUESTIONS;
  
  struct QuestionCycle {
    uint CID; // CID is cycle ID
    uint QID; // QID is question ID
    uint currentStartDate; //Current new start date, First time it is same as intitialStartDate, updated by result-declaration
    uint currentSubmitEndDate; // Updated when question first triggered
    uint currentCommitDateStart;
    uint currentCommitDateEnd;
    uint currentResultDate;
    uint nextStartDate;
    address[] usersAnswered; // array of UIDs who attempted the Que {UIDs... }
    address[] usersCommitted; // array of UIDs who committed the Que {UIDs... }
    string[] committedAnswerTexts; //array of committed answer texts
    uint NofAnswersGiven;
    uint NofAnswersLimit;
    bool rewardCalculated;
    string winningAnswer;
  }
  
  // The addQuestions method not only adds each question to the "QUESTIONS" array, but also adds the same Question to the 
  // "CURRENT_Questions" array with the appropriate dates. 
  // So every question will be in the CURRENT_Questions array with the current or upcoming dates setup and will be used
  // to maintain UIDs of users answering the question.
  // uint is QID of QUESTIONS
  mapping (uint => QuestionCycle) public CURRENT_Questions;
  
  struct UserAnswer {
    Status status;
    address sender;
    uint submittedDate;
    uint committedDate;
    uint resultDate;
    string answer;
  }
  
  // uint is QID of QUESTIONS
  mapping(uint => UserAnswer) public QIDAnswers; // Question wise Answers (persumably for one user)
  
  // Per User answer data
  struct UserAnswers {
    Status status;
    uint UserSubmittedQuestions; // CID submitted by one User
    uint UserCommittedQuestions; // CID committed by one User
    uint submittedDate;
    uint committedDate;
    uint resultDate;
    string answer;
    bool submitted;
    bool committed;
  }
  
  mapping(address => UserAnswers[]) public CURRENT_UserAnswers; //All questions answered by each user
  
  constructor(address _address) public {
    dateTimeUtils = DateTimeAPI(_address);
  }
  // add a question in the contract  
  function addQuestions (
    string _QuestionText,
    string _Answers,
    uint _AnswerCount,
    uint _NofAnswersLimit,
    uint _IntitialStartDate,
    uint _NofDays_Submit,
    uint _NofDays_Commit,
    uint _NofDays_BeforeResult,
    uint _NofDays_RepeatAfterResult,
    uint _RepeatCount,
    uint _Cost
  ) public onlyOwner returns (bool success) {
    
    QUESTIONS[TOTAL_NofQUESTIONS].QuestionText = _QuestionText;
    QUESTIONS[TOTAL_NofQUESTIONS].Answers = _Answers;
    QUESTIONS[TOTAL_NofQUESTIONS].AnswerCount = _AnswerCount;
    QUESTIONS[TOTAL_NofQUESTIONS].NofAnswersLimit = _NofAnswersLimit;
    QUESTIONS[TOTAL_NofQUESTIONS].IntitialStartDate = _IntitialStartDate;
    QUESTIONS[TOTAL_NofQUESTIONS].NofDays_Submit = _NofDays_Submit;
    QUESTIONS[TOTAL_NofQUESTIONS].NofDays_Commit = _NofDays_Commit;
    QUESTIONS[TOTAL_NofQUESTIONS].NofDays_BeforeResult = _NofDays_BeforeResult;
    QUESTIONS[TOTAL_NofQUESTIONS].NofDays_RepeatAfterResult = _NofDays_RepeatAfterResult;
    QUESTIONS[TOTAL_NofQUESTIONS].RepeatCount = _RepeatCount;
    QUESTIONS[TOTAL_NofQUESTIONS].Cost = _Cost;
    QUESTIONS[TOTAL_NofQUESTIONS].repeatFlag = 1;
    
    addQuestionCycle(CYCLE_ID, TOTAL_NofQUESTIONS);
    
    return true;
  }
  
  // add question for first cycle Next will auto insert on first cycle completion.
  function addQuestionCycle(
    uint _cid,
    uint _qid
  ) internal onlyOwner returns(bool success) {
      
    CURRENT_Questions[_cid].CID = _cid;
    CURRENT_Questions[_cid].QID = _qid;
    CURRENT_Questions[_cid].currentStartDate = QUESTIONS[_qid].IntitialStartDate;
    CURRENT_Questions[_cid].currentSubmitEndDate = CURRENT_Questions[_cid].currentStartDate + QUESTIONS[_qid].NofDays_Submit;
    CURRENT_Questions[_cid].currentCommitDateStart = CURRENT_Questions[_cid].currentSubmitEndDate;      
    TOTAL_NofQUESTIONS++;
    CYCLE_ID++;
    return true;
  } 
  /*code removed due to NDA*/
  //::::
  //::::
  //::::
   /*code removed due to NDA*/

  // Withdraw ether to owners accont
  function withdrawAmount(uint amount) public onlyOwner returns(bool) {
    uint _totalWithdrawableAmount;
    uint _totalAmount;
    (_totalWithdrawableAmount,_totalAmount) = getWithrawableAmount();
    require(amount <= _totalWithdrawableAmount, "amount is greater than withdrawable amount.");
    owner.transfer(amount);
    return true;
  }
}
