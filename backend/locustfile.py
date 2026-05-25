"""Load Testing for CropSphere Backend."""
from locust import HttpUser, task, between


class CropSphereUser(HttpUser):
    wait_time = between(1, 3)

    @task(3)
    def health_check(self):
        """Test public health endpoint."""
        self.client.get("/api/health")

    @task(2)
    def admin_without_token(self):
        """Test JWT protection — no token."""
        self.client.get(
            "/api/health/admin/status",
            name="/api/health/admin/status [no token]"
        )

    @task(1)
    def yield_without_token(self):
        """Test yield endpoint protection."""
        self.client.post(
            "/api/yield/predict",
            json={
                "crop": "Carrot",
                "rainfall": 500,
                "temperature": 25,
                "humidity": 80,
                "month": 6,
                "area": 100
            },
            name="/api/yield/predict [no token]"
        )