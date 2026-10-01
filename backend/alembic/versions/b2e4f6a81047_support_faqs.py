"""Versioned support knowledge base, writable only through the admin API."""
from datetime import datetime, timezone

from alembic import op
import sqlalchemy as sa

revision = "b2e4f6a81047"
down_revision = "d5f9a3b72104"
branch_labels = None
depends_on = None


def upgrade():
    table = op.create_table("support_faqs",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("slug", sa.String(80), nullable=False, unique=True),
        sa.Column("category", sa.String(24), nullable=False),
        sa.Column("question", sa.String(200), nullable=False),
        sa.Column("answer", sa.Text(), nullable=False),
        sa.Column("audience", sa.String(10), nullable=False),
        sa.Column("published", sa.Boolean(), nullable=False),
        sa.Column("sort_order", sa.Integer(), nullable=False),
        sa.Column("version", sa.Integer(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("audience IN ('all','client','driver')", name="ck_support_faq_audience"),
        sa.CheckConstraint("category IN ('requests','payments','account','safety')", name="ck_support_faq_category"),
        sa.CheckConstraint("version >= 1", name="ck_support_faq_version"),
    )
    op.create_index("ix_support_faq_visible", "support_faqs", ["published", "audience", "sort_order", "id"])
    rows = [
        ("preparar-carga", "requests", "¿Cómo describo mi carga?",
         "Indica qué necesitas transportar, agrega fotos y describe el acceso al retiro y a la entrega. Si no conoces el peso, indica que es aproximado y revisa la recomendación de vehículo antes de confirmar.", "client"),
        ("estado-flete", "requests", "¿Dónde reviso el estado de mi flete?",
         "Abre Mis fletes y selecciona el servicio. Allí puedes revisar su estado y, cuando corresponda, los datos del conductor y el chat. Si necesitas ayuda, escribe a soporte indicando el número del flete.", "client"),
        ("estado-pago", "payments", "¿Qué hago si tengo una duda sobre un cobro?",
         "Revisa el estado del pago en el detalle del flete. Si el resultado no está claro, contacta a soporte antes de repetir el pago e indica el número del flete y la fecha. No envíes datos completos de tu tarjeta, claves ni códigos de seguridad.", "all"),
        ("cambiar-solicitud", "requests", "¿Cómo consulto por un cambio o cancelación?",
         "Revisa las opciones disponibles y las condiciones que muestra el detalle de tu flete antes de confirmar una acción. Si necesitas asistencia, escribe a soporte con el número del flete. No se confirma un cambio ni una devolución solo por enviar el correo.", "all"),
        ("datos-cuenta", "account", "¿Cómo actualizo mi nombre o foto?",
         "Entra a Mi cuenta y abre Datos personales. Guarda los cambios del perfil y espera la confirmación al subir una foto. Si no se actualiza, vuelve a entrar a Mi cuenta o contacta a soporte.", "client"),
        ("ayuda-conductor", "requests", "Soy conductor, ¿cómo consulto por un viaje?",
         "Abre tus viajes y selecciona el servicio para revisar su estado. Para dudas de un viaje o liquidación, escribe a soporte indicando el número del flete y una descripción. No compartas contraseñas ni documentos personales por el chat del flete.", "driver"),
        ("seguridad-cuenta", "safety", "¿Qué información puedo enviar a soporte?",
         "Describe el problema e indica el número del flete, si corresponde. Nunca envíes contraseñas, códigos de acceso, datos completos de tarjetas ni documentos sensibles. El correo de soporte no sustituye a los servicios de emergencia.", "all"),
    ]
    op.bulk_insert(table, [dict(slug=slug, category=category, question=question,
        answer=answer, audience=audience, published=True, sort_order=index * 10,
        version=1, updated_at=datetime.now(timezone.utc))
        for index, (slug, category, question, answer, audience) in enumerate(rows)])
    if op.get_bind().dialect.name == "postgresql":
        op.execute("ALTER TABLE support_faqs ENABLE ROW LEVEL SECURITY")
        op.execute("REVOKE ALL ON support_faqs FROM PUBLIC")
        op.execute("REVOKE ALL ON SEQUENCE support_faqs_id_seq FROM PUBLIC")
        for role in ("anon", "authenticated"):
            if op.get_bind().execute(sa.text("SELECT 1 FROM pg_roles WHERE rolname = :role"), {"role": role}).scalar():
                op.execute(f"REVOKE ALL ON support_faqs FROM {role}")
                op.execute(f"REVOKE ALL ON SEQUENCE support_faqs_id_seq FROM {role}")


def downgrade():
    raise RuntimeError("Support content requires a reviewed forward migration")
