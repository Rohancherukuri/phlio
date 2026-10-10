Steps for test starting:- 

---for frontend---
cd frontend/ui
flutter run --dart-define=API_BASE_URL=http://192.168.1.6:8002/api/v1

---for backend---
cd backend
./scripts/Start-GraphDemo.ps1 -Seed