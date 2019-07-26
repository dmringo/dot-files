;; TODO: should I be using use-package here or in init.el?

;; This is almost certainly where mu4e will be installed, but it feels awfully
;; ugly
(add-to-list 'load-path "/usr/share/emacs/site-lisp/mu4e")

(require 'mu4e)
(require 'smtpmail)
(require 'message)

(use-package mu4e-alert
  :config
  (mu4e-alert-set-default-style 'log)
  (add-hook 'after-init-hook
            (defun my/mu4e-enable-alerts ()
              (mu4e-alert-enable-notifications)
              (mu4e-alert-enable-mode-line-display))))


(setq
 ;; Keep downloads consistent with other apps
 mu4e-attachment-dir "~/Downloads"
 ;; Prefer text over HTML (default)
 mu4e-view-prefer-html nil
 ;; This really forces text-view (see doc). Toggle with h in message view
 mu4e-view-html-plaintext-ratio-heuristic most-positive-fixnum
 ;; Don't update mailboxes automatically (default)
 mu4e-update-interval nil
 ;; Update headers if indexing changes them (default)
 mu4e-headers-auto-update t
 ;; I don't like signatures atm
 mu4e-compose-signature-auto-include nil
 ;; set format=flowed (https://joeclark.org/ffaq.html)
 mu4e-compose-format-flowed t
 ;; enable inline images (only relevant to HTML view, I assume)
 mu4e-view-show-images t
 ;; Don't save message - let IMAP do it
 mu4e-sent-messages-behavior 'delete
 ;; Have to set this when using mbsync
 mu4e-change-filenames-when-moving t
 ;; Don't keep buffer around when done with `message'
 message-kill-buffer-on-exit t
 ;; Don't reply to self 0_0
 mu4e-compose-dont-reply-to-self t
 ;; Show full addresses, not just names (toggle with M-<RET>)
 mu4e-view-show-addresses  t
 ;; my maildir is always here:
 mu4e-maildir "~/mail/"
 ;; use generic `completing-read' since it should be configued to use whatever
 ;; completion system I'm already invested in
 mu4e-completing-read-function 'completing-read
 ;; This has the effect of setting the point below the cited email in a message
 ;; reply.  For me, at least, bottom or inline posting style is preferable, but
 ;; 'traditional (which is nominally "inline") places the point as if for
 ;; top-posting.
 message-cite-reply-position 'below
 ;; Bit of a hack using the internal variable here, but I'd really like to be
 ;; able to use loopback pinentry with gpg (invoked by mbsync)
 mu4e~get-mail-password-regexp (concat "^Enter passphrase: $|" mu4e~get-mail-password-regexp)
 )

(setq old-mu4e-pwd-regex mu4e~get-mail-password-regexp)
(setq mu4e~get-mail-password-regexp (concat "^Enter passphrase: $\\|" old-mu4e-pwd-regex))

(defun my/mu4e-set-pandoc-fmt (fmt)
  (interactive (list (completing-read
                      "Select format: "
                      (split-string
                       ;; could work with internal var pandoc--formats from
                       ;; pandoc mode, but that feels wrong
                       (shell-command-to-string "pandoc --list-output-formats"))
                      nil 'require-match nil 'my/pandoc-fmt-hist)))
  ;; It would be better to verify that its a real format, but this is better
  ;; than nothing
  (setq fmt (or fmt "plain"))
  (let* ((old-cmd mu4e-html2text-command)
         (pandoc-ifmt "html-native_spans-native_divs")
         (pandoc-ofmt (shell-quote-argument fmt))
         ;; needed so pandoc doesn't choke on invalid bytes
         (iconv-opts "-c -t UTF-8")
         (cmd (format "iconv %s | pandoc -f %s -t %s"
                      iconv-opts pandoc-ifmt pandoc-ofmt)))
    ;; If nothing has changed, no need to set the mu4e var or refresh the display
    (unless (equal old-cmd cmd)
      (setq mu4e-html2text-command cmd)
      (when-let ((win (get-buffer-window mu4e~view-buffer-name)))
        (select-window win)
        (mu4e-view-refresh)))))

(bind-keys :map mu4e-view-mode-map
           ("c" . my/mu4e-set-pandoc-fmt)
           ("G" . mu4e-view-refresh))

(my/mu4e-set-pandoc-fmt "markdown")



;; use imagemagick for displaying images
(when (fboundp 'imagemagick-register-types)
  (imagemagick-register-types))

;; Add an action to view a message as HTML in the browser
(add-to-list 'mu4e-view-actions
             (cons "View in browser" 'mu4e-action-view-in-browser) t)

;; from https://www.reddit.com/r/emacs/comments/bfsck6/mu4e_for_dummies/elgoumx
(add-hook
 'mu4e-headers-mode-hook
 (defun my/mu4e-change-headers ()
   (interactive)
   (setq mu4e-headers-fields
         `((:human-date . 25) ;; alternatively, use :date
           (:flags . 6)
           (:from . 22)
           (:thread-subject . ,(- (window-body-width) 70)) ;; alternatively, use :subject
           (:size . 7)))))


(add-hook
 'mu4e-headers-search-hook
 (defun my/mu4e-switch-context-on-search (query)
   "Trys to switch the `mu4e' context intelligently by
checking for \"maildir:\" in a search query.  If the first path
element of the maildir in the query is not a context, this may
blow up."
   (if-let*
       ((_ (string-match "maildir:\\\"/\\([^/]+\\)/.*\\\"" query))
        (ctx (match-string 1 query)))
       (mu4e-context-switch nil ctx))))

(add-hook
 'mu4e-compose-mode-hook
 (defun my/mu4e-setup-compose ()
   "Setup function for composing email from `mu4e'"
   (flyspell-mode)))

(add-hook
 'mu4e-view-mode-hook
 (defun my/mu4e-setup-view ()
   "Setup function for viewing email from `mu4e'"
   (turn-on-visual-line-mode)))

;; There's probably a better way of doing this, rather than a complete redef.
;; `defadvice' doesn't seem to work so well though, since it's expecting that
;; the advised function will eventually be called.
(defun mu4e~context-ask-user (prompt)
  "Complete override of `mu4e-context-ask-user' for better completion.
This replicates the logic of the function it advises, but calls
`completing-read' rather than relying on unique first characters
of contexts"
  (when mu4e-contexts
    (let* ((names
            (cl-map 'list
                    (lambda (ctx)
                      (cons (mu4e-context-name ctx) ctx))
                    mu4e-contexts))
           (ctx-name (completing-read prompt names))
           (ctx (cdr-safe (assoc ctx-name names))))
      (or ctx (mu4e-error "No such context")))))


(defvar my/sendmail-prog "sendmail.sh"
  "Program to use for `my/sendmail'")
(defvar my/sendmail-args nil
  "Arguments to be given to `my/sendmail-prog' before any
  others")

(defun my/sendmail ()
  "My custom sendmail function using `my/sendmail-prog'.
Similar to `message-send-mail-with-sendmail' but simplified for
use with my msmtp wrapper \"sendmail.sh\". Arguments are solely determined by
`my/sendmail-args'"
  (require 'message)
  (let ((case-fold-search t))
    (save-restriction
      (message-narrow-to-headers))
    ;; Change header-delimiter to be what sendmail expects.
    (goto-char (point-min))
    (re-search-forward
     (concat "^" (regexp-quote mail-header-separator) "\n"))
    (replace-match "\n")

    (when message-interactive
      (with-current-buffer errbuf
        (erase-buffer))))
  (let* ((default-directory "/")
         (prog-with-args (cons my/sendmail-prog my/sendmail-args))
         (proc (make-process
                :name "my/sendmail process"
                :buffer "*my/sendmail stdout*"
                :stderr "*my/sendmail stderr*"
                :coding message-send-coding-system
                :command prog-with-args)))
    (if )
    (unless (or (null cpr) (and (numberp cpr) (zerop cpr)))
      (when errbuf
        (pop-to-buffer errbuf)
        (setq errbuf nil))
      (error "Sending...failed with exit value %d" cpr)))
  (when message-interactive
    (with-current-buffer errbuf
      (goto-char (point-min))
      (while (re-search-forward "\n+ *" nil t)
        (replace-match "; "))
      (if (not (zerop (buffer-size)))
          (error "Sending...failed to %s"
                 (buffer-string))))))




;; TODO: Use msmtp and `message-send-mail-with-sendmail'.

;; Probably can configure args to msmtp in the mu4e contexts, but it may be
;; better to just use a properly configured ~/.msmtprc
(cl-defmacro my/make-mu4e-context (name email smtp-spec &key match-fn vars)
  "wrapper for `make-mu4e-context' specific to my setup.
This references `mu4e-maildir', so make sure that's set."
  `(make-mu4e-context
    :name ,name
    :enter-func ,(lambda () (mu4e-message "Entering context: [%s]" name))
    :leave-func ,(lambda () (mu4e-message "Leaving context: [%s]" name))
    :match-func
    ,(or match-fn
         `(lambda (msg)
            (and msg
                 (mu4e-message-contact-field-matches
                  msg '(:to :cc :bcc) ,email))))
    :vars
    (quote
     ((user-mail-address          . ,email)
      (mu4e-sent-folder           . ,(f-join "/" name "sent"))
      (mu4e-drafts-folder         . ,(f-join "/" name "drafts"))
      (mu4e-trash-folder          . ,(f-join "/" name "trash"))
      (mu4e-refile-folder         . ,(f-join "/" name "archive"))
      (smtpmail-queue-dir         . ,(f-join mu4e-maildir name "q"))
      (send-mail-function         . sendmail-send-it)
      (message-send-mail-function . sendmail-send-it)
      (smtpmail-debug-info        . t)
      (smtpmail-debug-verbose     . t)
      (mu4e-get-mail-command      . ,(format "mbsync %s" name))
      ;; split the smtp-spec as host:port.  Anything else is an error
      ,(pcase (split-string smtp-spec ":")
         (`(,host ,port)
          (let ((prog (format
                       "sendmail.sh %s %s %s %s"
                       name my/location host port)))
            (cons 'sendmail-program prog)))
         (_ (error "Bad `smtp-spec': %S" smtp-spec)))
      ,@vars))))


;; Contexts
(setq mu4e-contexts
      (list
       (my/make-mu4e-context
        "dmr"
        "davidmringo@gmail.com"
        "smtp.gmail.com:587")
       (my/make-mu4e-context
        "lanl"
        "dringo@lanl.gov"
        "mail.lanl.gov:25")))

;; shortcut
(mu4e-bookmark-define
 "to:dringo@lanl.gov AND maildir:/inbox"
 "LANL inbox only"
 ?l)


(provide 'my-email)
