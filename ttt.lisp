;;;; This is the code for playing regular tic-tac-toe.
(in-package :server)
(syntax:use-syntax :clamp)

(defparameter dims* 5 "The side length of the tic-tac-toe board.")

(deftem (tic-tac-toe (:conc-name nil) (:include game))
  (need 2) ; The number of players needed to play a game.
  current
  (board (make-array (list dims* dims*) :initial-element nil)))

(defmethod print-object ((game tic-tac-toe) stream)
  (let *standard-output* stream
    (up r 0 dims*
      (up c 0 dims*
        (prf "~:[ ~;~:*~A~]" game!board.r.c)
        (unless (is c (dec dims*))
          (pr "|")))
      (prn)
      (unless (is r (dec dims*))
        (prn (make-string (+ dims* dims* -1) :initial-element #\-))))))

(defmethod start-game ((game tic-tac-toe))
  "Initialize the actual game."
  (= game!current (car game!players))
  (= (temp-cont game!current!socket) (play-ttt-turn game))
  (push game!current!socket sockets*)
  (send-hu game!players "~A" game ())
  
  (send-hu game!current "It is your turn.~%")
  (send-hu game!next    "It is your opponents turn.~%")
  
  (send-ai game!current "0~%")
  (send-ai game!next    "1~%"))

(defcont play-ttt-turn (game) (socket)
  "Performs a turn for the current player."
  (declare (ignore socket))
  (mvb (r c) (read-input game game!current)
    (= game!board.r.c (if (is game!current game!players!car) 'x 'o))
    (send-hu game!players "~A" game ())
    (aif (winner game)
      (do (announce-winner game)
          (disconnect game))
      (do ;; We only want to send the move if the game is still going
          ;; on. If the game is over, there is no reason to send the
          ;; opponents move.
          (send-ai game!next "~A ~A~%" r c)
          (= game!current (next game))
          (send-hu game!current "Your turn.~%" ())
          (push game!current!socket sockets*)
          (= (temp-cont game!current!socket) (play-ttt-turn game))))))

(def winner (game)
  "Is there a winner of this game? If so return the piece of that player."
  ;; By using and in the way below, thereturn value will be the
  ;; winning player.
  (or (iter (for r from 0 below dims*)
            (thereis (iter (for c from 0 below dims*)
                           (always (and (is game!board.r.c game!board.r.0) game!board.r.0)))))
      (iter (for c from 0 below dims*)
            (thereis (iter (for r from 0 below dims*)
                           (always (and (is game!board.r.c game!board.0.c) game!board.0.c)))))
      (and (iter (for i from 0 below dims*)
                 (always (and (is game!board.i.i game!board.0.0))))
           game!board.0.0)
      (and (iter (for r from 0 below dims*)
                 (for c from (dec dims*) downto 0)
                 (always (and (is game!board.r.c (get game!board.0 (dec dims*)))
                              game!board.r.c)))
           (get game!board.0 (dec dims*)))
      (and (iter out
                 (for r from 0 below dims*)
                 (iter (for c from 0 below dims*)
                       (in out (always game!board.r.c))))
           'tie)))

(def announce-winner (game)
  "Announce the winner of the game."
  (if (is (winner game) 'tie)
      (do (send-hu game!players "It was a tie.~%")
          (send-ai game!players "0~%"))
      (do (send-hu game!players "~:[Player 2~;Player 1~] won!~%" (is (winner game) 'x))
          (send-ai game!players "~:[-1~;1~]~%" (is (winner game) 'o)))))

(defmethod read-input ((game tic-tac-toe) player)
  (ttt-read-input game player))

(def ttt-read-input (game player)
  "Read the input for a tic-tac-toe game. The only reason this
   function exists is because the input methods for a human and for a
   computer are the same."
  (let line (read-line :from player!socket!socket-stream)
    (mvb (match strings) (scan-to-strings "^(\\d) (\\d)\\s*$" line)
      (unless match
        (error 'invalid-move
               :format-control "'~A' is malformed input."
               :format-arguments (list )))
      (let (r c) (map #'parse-integer strings)
        (unless (<= 0 r (dec dims*))
          (error 'invalid-move
                 :format-control "The row index ~A is illegal."
                 :format-arguments (list r)))
        (unless (<= 0 c (dec dims*))
          (error 'invalid-move
                 :format-control "The column index ~A is illegal."
                 :format-arguments (list r)))
        (when game!board.r.c
          (error 'invalid-move :format-control "The square is already taken."))
        (values r c)))))

