from pydantic import BaseModel, field_validator, Field


class PredictionInput(BaseModel):
    crop: str = Field(..., min_length=2, max_length=50)
    rainfall: float
    temperature: float
    humidity: float

    @field_validator('crop')
    @classmethod
    def crop_must_be_valid(cls, v):
        allowed = ['Carrot', 'Maize', 'Greengram',
                   'Cowpea', 'Fingermillet', 'Groundnut']
        if v not in allowed:
            raise ValueError(f'Invalid crop. Allowed: {allowed}')
        return v

    @field_validator('rainfall')
    @classmethod
    def rainfall_must_be_valid(cls, v):
        if v < 0 or v > 10000:
            raise ValueError('Rainfall must be between 0 and 10000')
        return v

    @field_validator('temperature')
    @classmethod
    def temperature_must_be_valid(cls, v):
        if v < -50 or v > 60:
            raise ValueError('Temperature must be between -50 and 60')
        return v

    @field_validator('humidity')
    @classmethod
    def humidity_must_be_valid(cls, v):
        if v < 0 or v > 100:
            raise ValueError('Humidity must be between 0 and 100')
        return v


class PriceInput(BaseModel):
    crop: str = Field(..., min_length=2, max_length=50)
    month: int

    @field_validator('month')
    @classmethod
    def month_must_be_valid(cls, v):
        if v < 1 or v > 12:
            raise ValueError('Month must be between 1 and 12')
        return v
