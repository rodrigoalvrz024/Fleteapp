from fastapi import Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse


async def safe_request_validation_error(
    request: Request, exc: RequestValidationError,
) -> JSONResponse:
    # Pydantic input, ctx, locations and custom validator messages can all contain
    # request values. Do not serialize or log them, including malformed JSON bodies.
    return JSONResponse(
        status_code=422,
        content={"detail": "Revisa los datos ingresados e intenta nuevamente."},
        headers={"Cache-Control": "no-store", "X-Content-Type-Options": "nosniff"},
    )
