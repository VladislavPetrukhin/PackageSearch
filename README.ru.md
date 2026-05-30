# PackageSearch

[English](README.md) · **Русский**

**PackageSearch** — десктопное приложение на GTK4/Libadwaita для ALT Linux, позволяющее искать, просматривать и устанавливать пакеты репозиториев **Sisyphus**, **p11**, **p10**, **p9**, **c10f2** и **c9f2**.

## Возможности

- **Поиск** по всем поддерживаемым веткам в пяти режимах:
  - по имени **исходного пакета**
  - по имени **бинарного пакета**
  - по **файлу** или пути
  - по **сопровождающему**
  - по номеру **задания** (task)
- Умный ввод: нечёткое ранжирование, нормализация кириллической раскладки и живой поиск с задержкой
- **История поиска** и горячие клавиши
- Просмотр полной **информации о пакете**:
  - Имя, версия, релиз, сопровождающий, группа, лицензия и домашняя страница
  - Краткое и полное описание
  - **Бинарные пакеты**, собранные из исходного
  - **Зависимости** в виде интерактивного графа
  - Сравнение **версий по веткам**
  - Разворачиваемый **changelog**
  - Просмотр **spec-файла**
  - **Загрузка** исходных и бинарных RPM
- Раздел **Безопасность**: закрытые уязвимости (CVE, BDU, GHSA) и известные баги Bugzilla с фильтром по статусу
- **Установка и обновление** пакетов из системного репозитория напрямую через `apt-get`
- Нативный интерфейс **GNOME/Adwaita** с быстрой и чистой навигацией
- Локализация (включая русский)

## Технологии

- [Vala](https://wiki.gnome.org/Projects/Vala)
- [GTK 4](https://www.gtk.org/) + [Libadwaita](https://gnome.pages.gitlab.gnome.org/libadwaita/doc/main/)
- [Blueprint](https://jwestman.pages.gitlab.gnome.org/blueprint-compiler/) для описания интерфейса
- [libalt-repo](https://altlinux.space/alt-gnome/libalt-repo) (привязки для Vala)
- Данные из [API репозиториев ALT Linux](https://rdb.altlinux.org/api/)

## Установка

```bash
# apt-get install -y meson ninja-build pkg-config vala gettext libadwaita-devel libjson-glib-devel libsoup3.0-devel libgee0.8-devel blueprint-compiler libgtk4-devel libgee0.8-gir-devel libjson-glib-gir-devel clang cmake gettext gettext-tools gobject-introspection-devel libalt-repo-vala-1-devel
$ git clone https://altlinux.space/vladislavpetrukhin/PackageSearch
$ cd PackageSearch
$ meson setup build --prefix=/usr
$ meson compile -C build
# meson install -C build
```

## Разработка

Запуск набора модульных тестов (чистая логика слоёв business/data — без UI и сети):

```bash
$ meson setup build-test
$ meson test -C build-test
```
