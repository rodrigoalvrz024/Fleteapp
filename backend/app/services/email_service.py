import requests

from app.core.config import settings


class EmailService:
    def send_password_reset(self, email: str, reset_url: str) -> None:
        if not settings.RESEND_API_KEY:
            print(f"[password-reset] Reset link for {email}: {reset_url}")
            return

        response = requests.post(
            "https://api.resend.com/emails",
            headers={
                "Authorization": f"Bearer {settings.RESEND_API_KEY}",
                "Content-Type": "application/json",
            },
            json={
                "from": settings.EMAIL_FROM,
                "to": [email],
                "subject": "Recupera tu contraseña de FleteApp",
                "html": self._password_reset_html(reset_url),
            },
            timeout=10,
        )
        response.raise_for_status()

    @staticmethod
    def _password_reset_html(reset_url: str) -> str:
        return f"""
        <div style="font-family:Arial,sans-serif;max-width:560px;margin:auto;color:#0f172a">
          <h2>Recupera tu contraseña</h2>
          <p>Recibimos una solicitud para cambiar la contraseña de tu cuenta FleteApp.</p>
          <p>
            <a href="{reset_url}" style="display:inline-block;background:#2563eb;color:#fff;
            padding:12px 18px;border-radius:8px;text-decoration:none;font-weight:600">
              Crear nueva contraseña
            </a>
          </p>
          <p>Este enlace vence pronto. Si no solicitaste este cambio, puedes ignorar este correo.</p>
        </div>
        """
