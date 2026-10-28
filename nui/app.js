const state = {
    currentScreen: 'loading',
    characters: []
};


const screens = {
    loading: document.getElementById('loading-screen'),
    characters: document.getElementById('character-screen')
};


const loadingText =
    document.getElementById('loading-text');

const characterList =
    document.getElementById('character-list');

function showScreen(screenName) {
    Object.values(screens).forEach((screen) => {
        screen.classList.remove('active');
    });

    const screen = screens[screenName];

    if (!screen) {
        return;
    }

    screen.classList.add('active');

    state.currentScreen = screenName;
}


function setLoadingText(text) {
    loadingText.textContent = text;
}


function renderCharacters(characters) {
    characterList.innerHTML = '';

    const slots = 3;

    for (let slot = 1; slot <= slots; slot++) {

        const character = characters.find(
            (item) => Number(item.slot) === slot
        );


        if (character) {

            const card =
                document.createElement('article');

            card.className =
                'character-card';

            card.innerHTML = `
                <span class="character-slot">
                    SLOT ${String(slot).padStart(2, '0')}
                </span>

                <h2 class="character-name">
                    ${escapeHtml(character.first_name)}
                    ${escapeHtml(character.last_name)}
                </h2>

                <p class="character-info">
                    ${escapeHtml(character.date_of_birth)}
                </p>

                <button
                    class="character-action"
                    data-slot="${slot}"
                >
                    GRAJ
                </button>
            `;


            const button =
                card.querySelector('.character-action');


            button.addEventListener(
                'click',
                () => selectCharacter(slot)
            );


            characterList.appendChild(card);

        } else {

            const card =
                document.createElement('article');

            card.className =
                'character-card empty';

            card.innerHTML = `
                <div class="empty-icon">
                    +
                </div>

                <h2 class="empty-title">
                    Nowa postać
                </h2>

                <p class="empty-description">
                    Slot ${String(slot).padStart(2, '0')}
                </p>
            `;


            card.addEventListener(
                'click',
                () => createCharacter(slot)
            );


            characterList.appendChild(card);
        }
    }
}


function selectCharacter(slot) {
    fetch(`https://${getResourceName()}/selectCharacter`, {
        method: 'POST',

        headers: {
            'Content-Type': 'application/json'
        },

        body: JSON.stringify({
            slot: slot
        })
    });
}


function createCharacter(slot) {
    fetch(`https://${getResourceName()}/createCharacter`, {
        method: 'POST',

        headers: {
            'Content-Type': 'application/json'
        },

        body: JSON.stringify({
            slot: slot
        })
    });
}


function escapeHtml(value) {
    const element =
        document.createElement('div');

    element.textContent =
        value ?? '';

    return element.innerHTML;
}


function getResourceName() {
    return typeof GetParentResourceName === 'function'
        ? GetParentResourceName()
        : 'mono_core';
}


/*
 * FiveM → NUI
 */

window.addEventListener('message', (event) => {

    const data = event.data;

    if (!data || !data.action) {
        return;
    }


    switch (data.action) {

        case 'showLoading':

            setLoadingText(
                data.text || 'Inicjalizowanie sesji...'
            );

            showScreen('loading');

            break;


        case 'showCharacters':

            state.characters =
                Array.isArray(data.characters)
                    ? data.characters
                    : [];

            renderCharacters(
                state.characters
            );

            showScreen('characters');

            break;

        case 'hide':
            Object.values(screens).forEach((screen) => {
                screen.classList.remove('active');
            });
            break;

        default:
            break;
    }
});

showScreen('loading');

fetch(`https://${getResourceName()}/nuiReady`, {
    method: 'POST',
    headers: {
        'Content-Type': 'application/json'
    },
    body: JSON.stringify({})
}).catch(() => {
});
