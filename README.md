# FileLock

`FileLock`은 macOS에서 파일을 잠그고 `.lock` 보호 파일로 관리하는 Objective-C 데스크톱 앱입니다.

## 주요 기능

- 일반 파일 또는 폴더를 `.lock` 보호 파일로 변환
- Finder에서 보호 파일을 더블클릭하면 비밀번호 입력 후 열기
- 잠금 파일 확장자 숨김
- 잠금 파일 이름 변경 / 삭제 방지 플래그 적용
- 관리자 전용 완전 해제 기능

## 프로젝트 구조

- `src/`: 앱 소스코드
- `assets/`: 앱 아이콘 및 로고 자산
- `build.sh`: 앱 번들 + 아이콘 + DMG까지 한 번에 빌드
- `package_dmg.sh`: `.app` 번들을 DMG로 패키징

## 로컬 빌드

macOS에서 아래 명령으로 앱과 DMG를 같이 빌드합니다.

```bash
bash build.sh
```

빌드 결과물:

- `dist/FileLock.app`
- `dist/FileLock.dmg`

## 설치

1. `FileLock.dmg`를 엽니다.
2. `FileLock.app`을 `Applications`로 드래그합니다.
3. 처음 실행 후 Finder에서 `.lock` 파일을 열면 FileLock이 연결됩니다.

## GitHub 업로드 방식

이 저장소에는 소스코드가 올라가고, macOS 설치 파일은 GitHub Releases에 올리는 방식을 권장합니다.

- 소스코드: 저장소 자체
- 설치 파일: `dist/FileLock.dmg`

태그 릴리스(`v1.0.0` 같은 형식)를 만들면 GitHub Actions가 자동으로 macOS 빌드와 DMG 아티팩트를 생성하도록 설정되어 있습니다.

## 릴리스 절차 예시

```bash
git tag v1.0.0
git push origin main
git push origin v1.0.0
```

그 뒤 GitHub Releases에서 소스코드 아카이브와 DMG를 함께 배포할 수 있습니다.
