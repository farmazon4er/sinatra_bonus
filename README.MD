Сначало вам необходимо сохранить тестовую базу в SQLITE3

gem install sqlite3

sqlite3

.open test.db

.save test

.exit 200;

Так же возможно нужно установить гемы из require плюс веб-сервер puma

gem install puma

gem install sequel

gem install sinatra

Для запуска выполните

ruby sintanra.rb
