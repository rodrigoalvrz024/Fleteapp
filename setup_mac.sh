#!/bin/bash

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "================================"
echo "  FleteApp — Setup Mac"
echo "================================"

echo -e "\n${BLUE}[1/5] Homebrew...${NC}"
if ! command -v brew &> /dev/null; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi
echo -e "${GREEN}✓ Homebrew listo${NC}"

echo -e "\n${BLUE}[2/5] Python 3.11...${NC}"
brew install python@3.11 2>/dev/null || true
export PATH="/opt/homebrew/opt/python@3.11/bin:$PATH"
echo -e "${GREEN}✓ Python listo${NC}"

echo -e "\n${BLUE}[3/5] PostgreSQL...${NC}"
brew install postgresql@15 2>/dev/null || true
brew services start postgresql@15
export PATH="/opt/homebrew/opt/postgresql@15/bin:$PATH"
sleep 2
psql postgres -c "CREATE USER fleteapp_user WITH PASSWORD 'fleteapp123';" 2>/dev/null || true
psql postgres -c "CREATE DATABASE fleteapp_db OWNER fleteapp_user;" 2>/dev/null || true
psql postgres -c "GRANT ALL PRIVILEGES ON DATABASE fleteapp_db TO fleteapp_user;" 2>/dev/null || true
echo -e "${GREEN}✓ PostgreSQL y BD listos${NC}"

echo -e "\n${BLUE}[4/5] Backend Python...${NC}"
cd backend
python3.11 -m venv venv
source venv/bin/activate
if [ ! -f ".env" ]; then
    cp .env.example .env
    echo -e "${YELLOW}⚠ .env creado — revísalo antes de correr${NC}"
fi
pip install --upgrade pip -q
pip install -r requirements.txt -q
cd ..
echo -e "${GREEN}✓ Backend listo${NC}"

echo -e "\n${BLUE}[5/5] Flutter...${NC}"
if command -v flutter &> /dev/null; then
    cd mobile
    flutter pub get
    cd ..
    echo -e "${GREEN}✓ Flutter dependencias instaladas${NC}"
else
    echo -e "${YELLOW}⚠ Flutter no encontrado — instálalo desde flutter.dev${NC}"
fi

echo ""
echo "================================"
echo -e "${GREEN}  ¡Listo para usar!${NC}"
echo "================================"
echo ""
echo "Terminal 1 — Backend:"
echo -e "  ${BLUE}cd backend && source venv/bin/activate && uvicorn app.main:app --reload${NC}"
echo ""
echo "Terminal 2 — Flutter:"
echo -e "  ${BLUE}cd mobile && flutter run${NC}"