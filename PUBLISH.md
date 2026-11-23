# Публикация отдельного репозитория на GitHub

Это уже готовая структура репозитория (README + `docs/`). Файлы можно опубликовать без правки.

## Вариант через GitHub (без консоли)

1. Открой <https://github.com/new>.
2. Название: `demo-exam-task1-manual` (или другое свободное).
3. Выбери Public или Private. **Не добавляй автоматически README**, он уже есть.
4. Создай репозиторий.
5. На странице пустого репозитория выбери **uploading an existing file** или **Add file → Upload files**.
6. Распакуй ZIP на компьютере, перетащи `README.md`, `PUBLISH.md` и **папку `docs` с сохранением путей**. Если GitHub-браузер не сохранил структуру папок, используй вариант через Git ниже.
7. Нажми **Commit changes**; проверь кликабельность ссылок оглавления.

## Вариант через Git (надёжнее для папок)

Распакуй архив, открой терминал **в папке `demo-exam-task1-manual`** и выполни:

```bash
git init -b main
git add .
git commit -m "Manual exam task 1: fast step-by-step guide"
git remote add origin https://github.com/ТВОЙ_ЛОГИН/demo-exam-task1-manual.git
git push -u origin main
```

Для `git push` нужна авторизация GitHub (например, Git Credential Manager, SSH-ключ или разрешённый персональный токен); пароль от аккаунта в терминал как Git-пароль не вводится. Если Git просит указать автора коммита, один раз настрой `git config --global user.name` и `git config --global user.email`.

После публикации адрес будет `https://github.com/ТВОЙ_ЛОГИН/demo-exam-task1-manual`.

> Архив представляет готовые файлы, но сам по себе **не является** созданным онлайн-репозиторием.