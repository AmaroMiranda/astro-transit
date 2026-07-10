"""POST /v1/transits/predict and GET /v1/transits/live (SPEC section 14).

The WebSocket loop re-runs the prediction service on an adaptive cadence (SPEC 11.4):
faster as the soonest candidate gets closer in time, slower when nothing is near.
"""

from __future__ import annotations

import asyncio
import contextlib

from fastapi import APIRouter, Depends, WebSocket, WebSocketDisconnect

from app.api.deps import get_prediction_service
from app.api.schemas import ObserverIn, PredictIn, PredictionOut
from app.domain.models import ObserverLocation
from app.services.prediction_service import PredictionService

router = APIRouter(prefix="/transits", tags=["transits"])


def _to_observer(o: ObserverIn) -> ObserverLocation:
    return ObserverLocation(
        latitude_deg=o.latitude,
        longitude_deg=o.longitude,
        altitude_m=o.altitude_m,
        horizontal_accuracy_m=o.horizontal_accuracy_m,
    )


@router.post("/predict", response_model=PredictionOut)
async def predict_transits(
    body: PredictIn,
    service: PredictionService = Depends(get_prediction_service),
) -> PredictionOut:
    response = await service.predict(
        observer=_to_observer(body.observer),
        targets=body.targets,
        horizon_s=body.horizon_seconds,
        radius_km=body.max_radius_km,
    )
    return PredictionOut.of(response)


def _next_poll_interval_s(response) -> float:
    """Adaptive polling cadence (SPEC 11.4)."""
    if not response.predictions:
        return 20.0
    soonest = response.predictions[0].candidate.time_to_transit_s
    if soonest < 30:
        return 2.0
    if soonest < 120:
        return 5.0
    return 10.0


@router.websocket("/live")
async def transits_live(
    websocket: WebSocket,
    service: PredictionService = Depends(get_prediction_service),
) -> None:
    await websocket.accept()
    try:
        params = await websocket.receive_json()
        observer = _to_observer(ObserverIn(**params["observer"]))
        targets = params.get("targets", ["sun", "moon"])
        radius_km = float(params.get("max_radius_km", 80.0))
        horizon_s = float(params.get("horizon_seconds", 120.0))

        previous_count = -1
        while True:
            response = await service.predict(
                observer=observer, targets=targets, horizon_s=horizon_s, radius_km=radius_km
            )
            out = PredictionOut.of(response)

            event = "prediction_updated" if response.predictions else "no_candidates"
            if previous_count > 0 and len(response.predictions) == 0:
                event = "transit_cancelled"
            previous_count = len(response.predictions)

            await websocket.send_json({"event": event, "data": out.model_dump(mode="json")})
            await asyncio.sleep(_next_poll_interval_s(response))
    except WebSocketDisconnect:
        pass
    except Exception as exc:  # pragma: no cover - defensive; keep the socket informative
        with contextlib.suppress(Exception):
            await websocket.send_json({"event": "error", "detail": str(exc)})
