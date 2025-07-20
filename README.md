# Dream Vacations App

A full-stack, containerized web application for exploring and managing travel destinations.

## Tech Stack

- **Frontend**: React
- **Backend**: Node.js (Express)
- **Database**: PostgreSQL
- **Containerization**: Docker & Docker Compose

## Features

- Browse and explore dream vacation destinations
- Persistent storage with PostgreSQL
- Fully containerized with Docker

## Getting Started

### Prerequisites

- [Docker](https://www.docker.com/get-started) installed
- [Docker Compose](https://docs.docker.com/compose/install/) installed
- [Git](https://git-scm.com/downloads) installed

### Installation

1. **Clone the repository**

   ```bash
   git clone https://github.com/Vivixell/ContainerizedApp.git

   cd ContainerizedApp
   ```
2. **Start the app**

```
docker-compose up --build
```

   This command builds the Docker images and starts the containers.

<img src="relevant_screenshots\buildCommand.png" alt="Build success" width="600">

**Successful build output:**

<img src="relevant_screenshots\buildSucces.png" alt="Build success" width="600">
Access the app

Open your browser and navigate to http://localhost to view the app.

<img src="relevant_screenshots\app.png" alt="Build success" width="600">

### Notes

* Ensure Docker is running before executing `docker-compose up`

* Stop containers with `docker-compose down` or use  `~docker-compose down -v --remove-orphans` to remove persistent volume.