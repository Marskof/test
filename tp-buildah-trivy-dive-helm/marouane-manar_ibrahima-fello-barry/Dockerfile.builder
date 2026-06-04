FROM maven:3.9-eclipse-temurin-17 AS builder
WORKDIR /app
COPY miage-bank-back/ /app/
RUN mvn clean package -DskipTests
