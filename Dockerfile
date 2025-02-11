FROM ruby:3.3
WORKDIR /usr/src/app
COPY . .
EXPOSE 80
RUN chmod +x ./index.rb
CMD ["./index.rb"]
