#pragma once
#include "BLEPeripheral.h"
#include "lib.h"

#include <stdint.h>
#include <string.h>

namespace toe
{

/*
 *button functions defined as function pointers
 */
typedef void (*button_func)();

/*
 *Button settings specified by developer
 */
class Button
{
  public:
    static int next_id;
    unsigned char id;
    unsigned char x;
    unsigned char y;
    unsigned char width;
    unsigned char height;
    bool border;
    char *text;
    char *image;

    explicit Button(unsigned char _x, unsigned char _y, unsigned char _width,
                    unsigned char _height, const char *_text)
        : x(_x), y(_y), width(_width), height(_height), border(true),
          text(nullptr), image(nullptr)
    {
        text = new char[50];
        strncpy(text, _text, 49);
    }

    explicit Button(unsigned char _x, unsigned char _y, unsigned char _width,
                    unsigned char _height, const char *_text, bool _border)
        : x(_x), y(_y), width(_width), height(_height), border(_border),
          text(nullptr), image(nullptr)
    {
        text = new char[50];
        strncpy(text, _text, 49);
    }

    explicit Button(unsigned char _x, unsigned char _y, unsigned char _width,
                    unsigned char _height, const char *_text, bool _border,
                    const char *_image)
        : x(_x), y(_y), width(_width), height(_height), border(_border),
          text(nullptr), image(nullptr)
    {
        text = new char[50];
        strncpy(text, _text, 49);
        if (_image != nullptr)
        {
            image = new char[256];
            strncpy(image, _image, 255);
        }
    }

    Button(const Button &rhs) = delete;
    Button(Button &&rhs)
        : x(rhs.x), y(rhs.y), width(rhs.width), height(rhs.height),
          border(rhs.border), text(rhs.text), image(rhs.image)
    {
        rhs.text = nullptr;
        rhs.image = nullptr;
    }

    ~Button()
    {
        if (text != nullptr)
            delete text;
        if (image != nullptr)
            delete image;
    }
};

template <typename Callable>
class ServerInterface
{
    // BLEPeripheral
    BLEPeripheral *ble;
    // Broadcast Name
    char device_name[11] = "toe-device";
    // Storage for Buttons
    Vector<Button *> btn_vec;
    // Mapping from Index to Function
    Vector<Callable> function_map;

    static unsigned async_process(void *, const unsigned char *data,
                                  unsigned len);

    /*
     *Send layout of buttons
     */
    bool send_layout();
    /*
     *Uses the function mapping to button command
     */
    bool call_function(unsigned char func_index);

  public:
    //////////////////////SETTINGS//////////////////////////////////
    /*
     *Create and store new button
     *RETURNS: Button id for function on success, -1 on failure
     */
    int add_button(Button btn, Callable func);
    /*
     *Sets the broadcast name for your device. Name can only be 10
     *characters
     *long
     *and default is toe-device. RETURNS true on success
     */
    bool set_device_name(const char *name);

    //////////////////////INTERFACE/////////////////////////////////
    /**
      * Constructs the object
      */
    ServerInterface();
    /**
     * Starts the server
     */
    bool start_server(/* parameters */);

    /**
     * In the case of a single threaded
     */
    bool process_command();

    /**
     * Stops the server if its running and destroys the object
     */
    ~ServerInterface();

    // Its going to be a bit harder to define how the communication works.
    // Probably do an example, then work it out
};

template <typename Callable>
ServerInterface<Callable>::ServerInterface() : ble(nullptr)
{
    Button::next_id = 0;
}

template <typename Callable>
ServerInterface<Callable>::~ServerInterface()
{
    if (ble != nullptr)
        delete ble;
}

template <typename Callable>
int ServerInterface<Callable>::add_button(Button btn, Callable func)
{
    if (btn_vec.size() == 16)
    {
        /*more than 16 buttons not currently supported*/
        return -1;
    }
    Button *button = new Button{static_cast<Button &&>(btn)};
    btn_vec.push_back(button);
    function_map.push_back(static_cast<Callable &&>(func));
    button->id = Button::next_id++;
    return button->id;
}

template <typename Callable>
bool ServerInterface<Callable>::set_device_name(const char *name)
{
    if (!name)
        return false;
    strncpy(device_name, name, 10);
    return true;
}
/*
 *
 */
template <typename Callable>
bool ServerInterface<Callable>::start_server(/* parameters */)
{
    ble = new BLEPeripheral(device_name);
    if (ble->allows_async())
    {
        ble->register_read_handler((void *)this, &async_process);
    }
    return true;
}

template <typename Callable>
unsigned ServerInterface<Callable>::async_process(void *self_,
                                                  const unsigned char *data,
                                                  unsigned len)
{
    ServerInterface *self = (ServerInterface *)self_;
    unsigned bytes_processed = 0;
    while (len >= 2)
    {
        unsigned char cmd;
        unsigned char func_index;
        cmd = *data++;
        func_index = *data++;
        switch (cmd)
        {
        case 0x00:
            /* do response for layout */
            self->send_layout();
            break;
        case 0x01:
            self->call_function(func_index);
            break;
        default:
            break;
        }
        bytes_processed += 2;
        len -= 2;
    }
    return bytes_processed;
}

template <typename Callable>
bool ServerInterface<Callable>::process_command()
{
    if (!ble)
    {
        return false;
    }
    if (ble->allows_async())
    {
        return false;
    }
    ble->process();
    if (ble->connected())
    {
        if (ble->bytes_available() >= 2) /*only read if we have a full package*/
        {
            unsigned char cmd;
            unsigned char func_index;
            cmd = (unsigned char)ble->read_byte();
            func_index = (unsigned char)ble->read_byte();
            switch (cmd)
            {
            case 0x00:
                /* do response for layout */
                send_layout();
                break;
            case 0x01:
                call_function(func_index);
                break;
            default:
                break;
            }
            return true;
        }
    }
    return false;
}

template <typename Callable>
bool ServerInterface<Callable>::call_function(unsigned char func_index)
{
    function_map[func_index]();
    return true;
}

template <typename Callable>
bool ServerInterface<Callable>::send_layout()
{
    if (!ble)
    {
        return false;
    }
    if (btn_vec.size() == 0)
        return false;
    unsigned char num_buttons = (unsigned char)btn_vec.size();
    ble->write(&num_buttons, 1);

    unsigned char buf[313];
    for (int i = 0; i < btn_vec.size(); i++)
    {
        buf[0] = btn_vec[i]->id;
        buf[1] = btn_vec[i]->x;
        buf[2] = btn_vec[i]->y;
        buf[3] = btn_vec[i]->width;
        buf[4] = btn_vec[i]->height;
        buf[5] = btn_vec[i]->border ? 1 : 0;
        /*If image being used send length*/
        unsigned char image_len = 0;
        if (btn_vec[i]->image)
            image_len = (unsigned char)strlen(btn_vec[i]->image);
        buf[6] = image_len;

        /*Copy in all strings*/
        strncpy((char *)(buf + 7), btn_vec[i]->text, 50);
        if (image_len)
            strncpy((char *)(buf + 57), btn_vec[i]->image, 256);

        unsigned len = 313;
        while (len > 0)
        {
            unsigned char sendLen = len > 64 ? 64 : len;
            ble->write(buf + 313 - len, sendLen);
            len = len > 64 ? len - 64 : 0;
            ble->process();
        }
    }
    return true;
}
}
