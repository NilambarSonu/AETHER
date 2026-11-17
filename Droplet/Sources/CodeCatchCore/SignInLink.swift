import Foundation

/// Finds the one action link in a sign-in, verification or password-reset mail
/// ("Confirm your sign-in", "Verify your email", magic links, "Reset password"),
/// not unsubscribe, help, social or tracking-pixel links. The subject decides the kind.
public enum SignInLink {
    public enum Kind: Sendable { case signIn, passwordReset }

    public static func find(in links: [MailLink], subject: String) -> (url: URL, kind: Kind)? {
        // "Your password was changed" is an alert, not a reset; course enrollment ("prijave") is not a sign-in.
        let kind: Kind
        if matches(resetContext, subject), !matches(passwordAlert, subject) {
            kind = .passwordReset
        } else if matches(context, subject), !matches(review, subject) {
            kind = .signIn
        } else {
            // Check if any link explicitly contains a high-confidence password reset button
            // (e.g. Razorpay, Slack, GitHub, or banks sending reset emails with generic/custom subject lines).
            if !matches(passwordAlert, subject),
               links.contains(where: {
                   guard let u = URL(string: $0.url.trimmingCharacters(in: .whitespaces)),
                         u.scheme?.lowercased() == "https",
                         let host = u.host, !host.isEmpty,
                         !matches(excluded, $0.url), !matches(excludedLabel, $0.label)
                   else { return false }
                   let target = u.path + "?" + (u.query ?? "")
                   return matches(resetAction, $0.label) && matches(actionPath, target)
               }) {
                kind = .passwordReset
            } else {
                return nil
            }
        }
        var best: (url: URL, score: Int)?
        for link in links {
            guard let url = URL(string: link.url.trimmingCharacters(in: .whitespaces)), url.scheme?.lowercased() == "https",
                let host = url.host, !host.isEmpty, !matches(excluded, link.url), !matches(excludedLabel, link.label)
            else { continue }
            // The button text must be the action; a matching path only ranks candidates.
            // In a sign-in alert, "Reset password" is the "this wasn't me" escape, not the sign-in.
            guard
                kind == .signIn
                    ? matches(action, link.label) && !matches(resetAction, link.label)
                    : matches(resetAction, link.label) || matches(action, link.label)
            else { continue }
            var score = 3
            if matches(actionPath, url.path + "?" + (url.query ?? "")) { score += 2 }
            if link.label.count <= 40 { score += 1 }
            if score > best?.score ?? 0 { best = (url, score) }
        }
        return best.map { ($0.url, kind) }
    }

    private static func rx(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p, options: .caseInsensitive) }

    private static let context = rx(
        #"\bverif(y|ication)\b|confirm (your )?(sign|log|e-?mail|account|identity|device)|sign[- ]?in (link|request|attempt|to)|log[- ]?in (link|request|attempt|code|to)|(secure|magic|one-time) link|activate your|approve (your )?(sign|log)|is (this|it) you|potrdi|\bpovezava za prijavo\b|\bprijav[ao] v (vaš )?(račun|profil|naročniški center)\b|aktivir|bestätig|anmeld|se connecter|connexion|iniciar sesión|acceder|entrar|acessar"#
    )
    /// "OAuth verification", "domain verification": a review of the reader's app or business, not a sign-in.
    private static let review = rx(#"\b(oauth|app|brand|domain|business|publisher) verification\b"#)
    private static let action = rx(
        #"\bverif(y|ication)\b|confirm|sign[- ]?in|log[- ]?in|magic|activat|approv|authori[sz]|yes|it'?s me|was me|continue|access link|access (your|my) (\w+ )?account|to access\b|potrdi|prijava|prijavi|aktiviraj|bestätig|anmelden|click here to (sign|log|verify|confirm)|se connecter|connexion|iniciar sesión|acceder|entrar|acessar|accedi"#
    )
    private static let actionPath = rx(#"verif|confirm|magic|log-?in|sign-?in|auth|activat|approv|token=|code=|otp|reset|password|recover"#)
    private static let resetContext = rx(
        #"\breset\s+(\w+\s+){0,3}password\b|\bpassword\s+(\w+\s+){0,3}(reset|recovery|assistance|change|setup|instructions|link)\b|\b(forgot|forgotten|change|set|create|choose|recover|restore|update)\s+(\w+\s+){0,3}(new\s+)?password\b|\breset\s+(\w+\s+){0,2}(link|request|instructions|code|access)\b|\bnew\s+password\b|passwort\s*(zurücksetzen|vergessen|ändern)|ponastavi(tev)?\s*gesl|pozablje\w*\s*gesl|novo\s*geslo|recuperar\s*(senha|contraseña)|redefinir\s*senha|restablecer\s*contraseñ\w*|mot\s*de\s*passe\s*oublié|réinitialisation|reinitialisation"#
    )
    private static let passwordAlert = rx(
        #"password (was|has been) (changed|updated|reset)|password (changed|updated)|(changed|updated) your password|success|passwort (wurde )?geändert|geslo (je bilo )?spremenjeno"#
    )
    private static let resetAction = rx(
        #"\b(reset|change|set|create|choose|recover|restore|update)\s+(\w+\s+){0,2}password\b|\b(reset|passwort|geslo|wachtwoord|lösenord|hasło|parola|şifre|contraseñ\w*|senha|mot de passe)\b|ponastavi|zurücksetzen|réinitialiser|reinitialiser|restablecer|redefinir|reimposta|secure your|recover account"#
    )
    private static let excluded = rx(
        #"unsubscribe|optout|opt-out|preferences|privacy|/terms|/legal|/help|support\.|/support|mailto:|facebook\.com|twitter\.com|//x\.com|linkedin\.com|instagram\.com|youtube\.com|tiktok\.com/@|apps\.apple\.com|play\.google\.com|\.(png|jpe?g|gif|svg)(\?|$)"#
    )
    private static let excludedLabel = rx(
        #"unsubscribe|view (it )?in (your )?browser|privacy|terms|help center|contact us|didn'?t|not you|wasn'?t (me|you)|report"#)
}
