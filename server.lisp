;;;; This is the code for the main server.
(in-package :server)
(syntax:use-syntax :clamp)

(define-condition game-error (simple-error) ())
(define-condition invalid-move (game-error) ())

(defparameter sockets* '()
  "A list of all of the sockets we need to listen for. This includes
  all of the sockets that may disconnect.")

(defparameter socket->game* (table)
  "A table mapping each socket to the game it is associated with. This
   is in case a player close all of the other sockets.")

(defparameter game->sockets* (table)
  "A table mapping from a game to all of the sockets we need to
   disconnect if a player disconnects.")

;; (def start-server (game-type ports &rest args)
;;   "Start a server playing a game of type GAME"
;;   (unwind-protect (do (each port (mklist ports)
;;                         (with (game (apply #'inst game-type args)
;;                                     listener (socket-listen *wildcard-host* port :reuse-address t))
;;                           (push listener sockets*)
;;                           (= conts*.listener (add-player game))))
;;                       (listening-loop))
;;     (mapc #'safely-close sockets*)
;;     (= sockets* '())))

;; (def start-server (game-type hport aport &rest args)
;;   "Start a server playing a game of type GAME. This opens two
;;     sockets. One for aiplayers and one for human players."
;;   (unwind-protect (do (let game (apply #'inst game-type args)
;;                         (let listener (socket-listen *wildcard-host* hport :reuse-address t)
;;                           (push listener sockets*)
;;                           (push listener game->sockets*.game)
;;                           (= (cont listener) (add-player game 'human)))
;;                         (let listener (socket-listen *wildcard-host* aport :reuse-address t)
;;                           (push listener sockets*)
;;                           (push listener game->sockets*.game)
;;                           (= (cont listener) (add-player game 'ai))))
;;                       (listening-loop))
;;     (mapc [disconnect _ t] (keys game->sockets*))))

(def start-server (game-type port &rest args)
  "This version of start-server opens a single server which connects
   every two to a game of ttt. There is no limit on the number of
   players."
  (let listener (socket-listen *wildcard-host* port :reuse-address t)
    (unwind-protect (do (push listener sockets*)
                        ;(push listener game->sockets*.current-game*)
                        (= (cont listener) (add-player (apply #'inst game-type args) 'ai))
                        (listening-loop))
      (mapc [disconnect _ t] (keys game->sockets*))
      (socket-close listener)
      (= sockets* (rem listener sockets*))
      (rem-cont listener))))

(def listening-loop ()
  "The main loop for listening."
  (while sockets*
    (let sockets (wait-for-input sockets* :ready-only t)
      (each socket sockets
        (aif2 (and (~isa socket 'stream-server-usocket)
                   (is socket (peek-char nil (socket-stream socket) nil socket)))
                ;; We need to go through the loop again since we may
                ;; have disconnected some of the other ready sockets.
                (do (disconnect socket->game*.socket t)
                    (return))
              (cont socket)
                (call it socket)
              (temp-cont socket)
                (restart-case (call it socket)
                  (restart-turn ()
                    :report "Restart the current player's turn."
                    (= (temp-cont socket) it)
                    (send-hu socket->game*.socket!current "Enter a legal move.~%"))
                  (disconnect ()
                    :report "Disconnect the current game."
                    (disconnect socket->game*.socket t) (return)))
              :else
                (do (restart-case (error "No continuation for socket ~A." socket)
                      (ignore-input ()
                        :report "Ignore all of the new information from the socket."
                        (while (listen socket!socket-stream)
                          (read-line :from socket!socket-stream))))))))))

(def disconnect (game ? pdisc)
  "Disconnect a game."
  (when pdisc
    (send-hu game!players "A player disconnected, terminating the game.~%")
    (send-ai game!players "-1~%"))
  (zap #'set-difference sockets* game->sockets*.game)
  (each socket game->sockets*.game
    (remhash socket socket->game*)
    (rem-cont socket)
    (rem-temp-cont socket)
    (socket-close socket))
  (remhash game game->sockets*))

(defcont add-player (game type) (listener)
  "Wait for all of the players to connect."
  (withs (socket (socket-accept listener)
          player (inst type :socket socket))
    (push socket game->sockets*.game)
    (push socket sockets*)
    (= socket->game*.socket game)
    (push player game!players)
    (when (is game!players!len game!need)
      ;; (let listeners (set-difference game->sockets*.game (map #'socket game!players))
      ;;   (= game->sockets*.game (set-difference game->sockets*.game listeners))
      ;;   (= sockets* (set-difference sockets* listeners))
      ;;   (mapc #'socket-close listeners))

      (start-game game)
      ;; Have the continuation add players to a new game instead of
      ;; the current one. It is safe to use type-of as it will always
      ;; return the class-name of a class with a proper name.
      (= game (inst (type-of game))))))
