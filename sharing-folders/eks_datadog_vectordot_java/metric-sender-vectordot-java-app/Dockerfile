FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /app
COPY pom.xml .
RUN mvn -q -e -DskipTests dependency:resolve
COPY src ./src
RUN mvn -q -e -DskipTests package

FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build /app/target/metric-sender-vectordot-java-1.0.0.jar /app/app.jar
COPY --from=build /app/target/dependency/ /app/lib/
RUN useradd -u 10001 juser
USER juser
ENV DOGSTATSD_HOST=127.0.0.1
ENV DOGSTATSD_PORT=8125
CMD ["sh", "-lc", "java -cp app.jar:lib/* com.example.DogstatsdPing"]
