# Contributing to TripCrew

Thank you for contributing to TripCrew! This guide establishes our team's standard git workflow, branching strategy, and code quality standards to ensure smooth collaboration.

---

## 🌳 Branching Strategy

Our repository uses a structured, branch-based collaboration model:

- **`main`**: The primary, stable branch. Code in `main` should always build cleanly, pass all tests, and be deployable.
- **`develop`** (optional/staging): Integration branch for testing bundled feature sets before release to `main`.
- **`feature/<name>`**: For new features or enhancements.
- **`fix/<name>`**: For bug fixes or patch releases.

### Branch Naming Examples
- `feature/tripcrew-pay-ui`
- `feature/live-crew-map`
- `fix/join-permission`
- `fix/mobile-layout-overflow`

---

## 🔄 Development Workflow

### 1. Synchronize with Main
Always start from the latest code on `main`:
```bash
git checkout main
git pull origin main
```

### 2. Create a Feature Branch
Create a descriptive branch for your task:
```bash
git checkout -b feature/your-feature-name
```

### 3. Make Your Changes
- Follow Flutter and Dart conventions (`dart format .`).
- Write meaningful automated unit/widget tests for new logic in `test/`.
- Ensure no sensitive information or `.env` files are added.

### 4. Run Quality Checks Locally
Before committing, verify that your changes satisfy our quality gate:
```bash
dart format .
flutter analyze
flutter test
```
All tests must pass and `flutter analyze` must report zero issues.

### 5. Commit Your Changes
Write clear, conventional commit messages:
```bash
git add .
git commit -m "feat: add real-time trip pulse reaction animations"
```

### 6. Push to GitHub
Push your branch to the remote repository:
```bash
git push -u origin feature/your-feature-name
```

### 7. Open a Pull Request (PR)
1. Go to [https://github.com/gnanoognanoo/trip-crew](https://github.com/gnanoognanoo/trip-crew).
2. Open a Pull Request from your branch into `main`.
3. Provide a clear description of the change, test results, and any relevant screenshots.
4. Request a review from at least one teammate.
5. Once approved and checks pass, merge into `main`.

> [!IMPORTANT]
> **Do not push unreviewed changes directly to `main`.** Always use Pull Requests for major modifications.

---

## 🔐 Security & Secrets Policy

1. **Never commit `.env` or configuration files with real secrets.**
   - All environment files (`.env`, `server/.env`) are strictly ignored in `.gitignore`.
   - Use `.env.example` and `server/.env.example` for templates.
2. **Never commit service-account JSON, private keys, or keystores.**
3. Client configuration files (`google-services.json`, `firebase_options.dart`) contain only public client identifiers and are safe for client-side builds.
4. The Cloudinary integration uses unsigned client presets; do not add API secrets to client code.

---

## 💬 Code Review Checklist

Before approving a PR, reviewers should verify:
- [ ] Code formatted with `dart format .`
- [ ] `flutter analyze` passes with zero warnings or errors
- [ ] `flutter test` passes all tests
- [ ] No hardcoded API secrets or passwords
- [ ] Atomic Firestore security rules respected (no counter drift, no role escalation)
- [ ] UI is responsive and tested on multiple device sizes
